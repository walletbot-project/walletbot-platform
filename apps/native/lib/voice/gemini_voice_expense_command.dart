import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/data.dart';
import '../sync/wire.dart';
import '../telemetry/agent_metrics.dart';
import 'pcm_audio_player.dart';
import 'tool_executors.dart';
import 'voice_event.dart';
import 'voice_expense_command.dart';
import 'voice_session_remote_sync.dart';
import 'voice_session_repository.dart';

class GeminiVoiceExpenseCommandFactory implements VoiceExpenseCommandFactory {
  GeminiVoiceExpenseCommandFactory({
    required this.repositories,
    required this.sessionRepository,
    this.remoteSync,
    this.agentMetrics,
    this.useAuthenticatedTokenAction = false,
    this.sessionToken,
    ConvexClient? convexClient,
    this.apiKey = const String.fromEnvironment('GEMINI_API_KEY'),
    this.liveToken = const String.fromEnvironment('GEMINI_LIVE_TOKEN'),
    this.convexSiteUrl = const String.fromEnvironment('CONVEX_SITE_URL'),
  }) : convexClient = convexClient ?? ConvexClient.instance;

  final AppRepositories repositories;
  final VoiceSessionRepository sessionRepository;
  final VoiceSessionRemoteSync? remoteSync;
  final AgentMetrics? agentMetrics;
  final bool useAuthenticatedTokenAction;
  final String? sessionToken;
  final ConvexClient convexClient;
  final String apiKey;
  final String liveToken;
  final String convexSiteUrl;
  GeminiVoiceExpenseCommand? _active;

  @override
  VoiceExpenseCommand? get activeCommand {
    final active = _active;
    return active != null && active.isActive ? active : null;
  }

  @override
  VoiceExpenseCommand create() {
    final existing = activeCommand;
    if (existing != null) return existing;
    late final GeminiVoiceExpenseCommand command;
    command = GeminiVoiceExpenseCommand(
      repositories: repositories,
      sessionRepository: sessionRepository,
      remoteSync: remoteSync,
      agentMetrics: agentMetrics,
      useAuthenticatedTokenAction: useAuthenticatedTokenAction,
      sessionToken: sessionToken,
      convexClient: convexClient,
      apiKey: apiKey,
      liveToken: liveToken,
      convexSiteUrl: convexSiteUrl,
      onEnded: () {
        if (identical(_active, command)) _active = null;
      },
    );
    _active = command;
    return command;
  }

  Future<void> dispose() async {
    await _active?.dispose();
    _active = null;
    await remoteSync?.dispose();
  }
}

class GeminiVoiceExpenseCommand implements VoiceExpenseCommand {
  GeminiVoiceExpenseCommand({
    required this.repositories,
    required this.sessionRepository,
    required this.remoteSync,
    required this.agentMetrics,
    required this.useAuthenticatedTokenAction,
    required this.sessionToken,
    required this.convexClient,
    required this.apiKey,
    required this.liveToken,
    required this.convexSiteUrl,
    required this.onEnded,
  }) : _executors = ToolExecutors(repositories);

  static const _model = 'gemini-3.1-flash-live-preview';
  static const _voiceName = 'Kore';
  static const _maxQueuedMessages = 200;
  static const _tokenRefreshMargin = Duration(minutes: 2);

  final AppRepositories repositories;
  final VoiceSessionRepository sessionRepository;
  final VoiceSessionRemoteSync? remoteSync;
  final AgentMetrics? agentMetrics;
  final bool useAuthenticatedTokenAction;
  final String? sessionToken;
  final ConvexClient convexClient;
  final String apiKey;
  final String liveToken;
  final String convexSiteUrl;
  final void Function() onEnded;
  final ToolExecutors _executors;
  final _audioPlayer = PcmAudioPlayer();
  final _events = StreamController<VoiceEvent>.broadcast();
  final List<VoiceEvent> _history = [];
  final List<Map<String, dynamic>> _pendingMessages = [];
  final Set<String> _cancelledToolIds = {};

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _goAwayTimer;
  Future<void>? _connectFuture;
  Completer<void>? _setupComplete;
  String? _sessionId;
  String? _resumeHandle;
  String? _effectiveToken;
  DateTime? _tokenExpiresAt;
  bool _active = false;
  bool _connected = false;
  bool _disposed = false;
  bool _explicitlyStopped = false;
  bool _audioPlaybackEnabled = true;
  bool _screenAttached = false;
  bool _discardInterruptedOutput = false;
  bool _audioStreamOpen = false;
  int _connectionGeneration = 0;
  int _reconnectAttempt = 0;
  int _inputChunks = 0;
  int _textMessages = 0;
  int _outputAudioChunks = 0;
  int _outputAudioBytes = 0;
  bool _sessionCostMetricSent = false;
  bool _toolCallSinceLastUsage = false;
  int _interactionSequence = 0;
  double? _lastInteractionTotalCostUsd;
  Map<String, Object?>? _latestUsageMetadata;

  @override
  String get label => 'Gemini Live voice expense command';

  @override
  Stream<VoiceEvent> get events async* {
    yield* Stream<VoiceEvent>.fromIterable(List.of(_history));
    yield* _events.stream;
  }

  @override
  bool get isActive => _active && !_explicitlyStopped && !_disposed;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> start({bool respondWithAudio = true}) async {
    _audioPlaybackEnabled = respondWithAudio;
    if (isActive) {
      if (!_connected) {
        _reconnectTimer?.cancel();
        await _connect();
      }
      return;
    }
    if (_disposed) throw StateError('Voice command is disposed');

    final session = await sessionRepository.openOrCreate(model: _model);
    _sessionId = session.id;
    _resumeHandle = session.resumeHandle;
    _active = true;
    _explicitlyStopped = false;
    remoteSync?.schedule(delay: Duration.zero);

    _emit(VoiceConnectingEvent('Connecting to Gemini Live'));
    await _audioPlayer.start(sampleRate: 24000);
    await _connect();
  }

  Future<void> _connect() {
    final existing = _connectFuture;
    if (existing != null) return existing;
    final future = _connectOnce();
    _connectFuture = future;
    return future.whenComplete(() {
      if (identical(_connectFuture, future)) _connectFuture = null;
    });
  }

  Future<void> _connectOnce() async {
    if (!isActive) return;
    final effectiveToken = await _resolveLiveToken();
    if (apiKey.isEmpty && effectiveToken.isEmpty) {
      throw StateError(
        'Missing Gemini credentials. Configure an authenticated Convex '
        'account, GEMINI_LIVE_TOKEN, or GEMINI_API_KEY.',
      );
    }

    final generation = ++_connectionGeneration;
    final uri = _connectionUri(effectiveToken);
    final setupComplete = Completer<void>();
    _setupComplete = setupComplete;
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    await sessionRepository.markStatus(_sessionId!, 'connecting');

    _subscription = channel.stream.listen(
      (message) => _handleServerMessage(message, generation),
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _connectionGeneration || !isActive) return;
        _emit(VoiceErrorEvent('WebSocket error: $error', isTransient: true));
        _persistProtocolEvent(
          type: 'websocket_error',
          direction: 'server',
          payload: {'error': error.toString(), 'stackTrace': '$stackTrace'},
        );
      },
      onDone: () => _handleSocketDone(channel, generation),
      cancelOnError: false,
    );

    final setup = <String, dynamic>{
      'setup': {
        'model': 'models/$_model',
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': _voiceName},
            },
          },
        },
        'inputAudioTranscription': <String, dynamic>{},
        'outputAudioTranscription': <String, dynamic>{},
        'sessionResumption': {
          if (_resumeHandle != null) 'handle': _resumeHandle,
        },
        'contextWindowCompression': {'slidingWindow': <String, dynamic>{}},
      },
    };
    _sendNow(setup);

    try {
      await setupComplete.future.timeout(const Duration(seconds: 20));
    } catch (_) {
      if (generation == _connectionGeneration) {
        await _closeSocket(invalidateGeneration: true);
      }
      rethrow;
    }
    if (generation != _connectionGeneration || !isActive) return;
    _connected = true;
    _reconnectAttempt = 0;
    await sessionRepository.markStatus(_sessionId!, 'active');
    _emit(VoiceConnectedEvent());
    _flushPendingMessages();
  }

  Future<String> _resolveLiveToken() async {
    if (liveToken.isNotEmpty) return liveToken;
    final cached = _effectiveToken;
    final expiresAt = _tokenExpiresAt;
    if (cached != null &&
        (expiresAt == null ||
            DateTime.now().add(_tokenRefreshMargin).isBefore(expiresAt))) {
      return cached;
    }

    _emit(VoiceSystemEvent('Requesting live token from Convex'));
    Map<String, Object?>? body;
    if (useAuthenticatedTokenAction) {
      try {
        final raw = await convexClient.action(
          name: 'v1/live/actions:requestLiveToken',
          args: const {},
        );
        final decoded = decodeConvexResponse(raw);
        if (decoded is! Map) {
          throw StateError('Malformed Convex live token response');
        }
        body = decoded.cast<String, Object?>();
      } catch (error) {
        _emit(VoiceSystemEvent('Authenticated token action failed: $error'));
      }
    }
    if (body == null) {
      if (convexSiteUrl.isEmpty) return '';
      final credential = sessionToken;
      if (credential == null || credential.isEmpty) return '';
      final base = Uri.parse(convexSiteUrl);
      final response = await http.post(
        base.replace(path: '/v1/live/token'),
        headers: {'Authorization': 'Bearer $credential'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Convex live token request failed: '
          '${response.statusCode} ${response.body}',
        );
      }
      body = (jsonDecode(response.body) as Map).cast<String, Object?>();
    }

    final token = body['token'];
    if (token is! String || token.isEmpty) {
      throw StateError('Convex live token response did not include token');
    }
    final expiration = body['expireTime'];
    _tokenExpiresAt = expiration is String
        ? DateTime.tryParse(expiration)
        : null;
    _effectiveToken = token;
    _emit(VoiceSystemEvent('Live token received for model: ${body['model']}'));
    return token;
  }

  Uri _connectionUri(String effectiveLiveToken) {
    const basePath = '/ws/';
    if (effectiveLiveToken.isNotEmpty) {
      return Uri(
        scheme: 'wss',
        host: 'generativelanguage.googleapis.com',
        path:
            '${basePath}google.ai.generativelanguage.v1alpha.'
            'GenerativeService.BidiGenerateContentConstrained',
        queryParameters: {'access_token': effectiveLiveToken},
      );
    }
    return Uri(
      scheme: 'wss',
      host: 'generativelanguage.googleapis.com',
      path:
          '${basePath}google.ai.generativelanguage.v1beta.'
          'GenerativeService.BidiGenerateContent',
      queryParameters: {'key': apiKey},
    );
  }

  @override
  Future<void> addAudioChunk(Uint8List chunk) async {
    if (!isActive) return;
    _inputChunks += 1;
    _audioStreamOpen = true;
    _persistProtocolEvent(
      type: 'audio_input_chunk',
      direction: 'client',
      modality: 'audio',
      payload: {'chunk': _inputChunks, 'byteLength': chunk.length},
      binaryData: Uint8List.fromList(chunk),
      binaryMimeType: 'audio/pcm;rate=16000',
    );
    _sendOrQueue({
      'realtimeInput': {
        'audio': {
          'data': base64Encode(chunk),
          'mimeType': 'audio/pcm;rate=16000',
        },
      },
    });
  }

  @override
  Future<void> endAudioStream() async {
    if (!isActive || !_audioStreamOpen) return;
    _audioStreamOpen = false;
    _sendOrQueue({
      'realtimeInput': {'audioStreamEnd': true},
    });
  }

  @override
  void setAudioPlaybackEnabled(bool enabled) {
    if (_audioPlaybackEnabled == enabled) return;
    _audioPlaybackEnabled = enabled;
    recordClientEvent('audio_playback_changed', {'enabled': enabled});
  }

  @override
  Future<void> sendText(String text) async {
    if (!isActive) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _textMessages += 1;
    await endAudioStream();
    recordClientEvent('send_message', {
      'interactionModality': 'text',
      'text': trimmed,
    });
    _sendOrQueue({
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': trimmed},
            ],
          },
        ],
        'turnComplete': true,
      },
    });
  }

  @override
  void recordClientEvent(
    String action, [
    Map<String, Object?> details = const {},
  ]) {
    if (!isActive) return;
    if (action == 'screen_attached') _screenAttached = true;
    if (action == 'screen_detached') _screenAttached = false;
    _emit(VoiceClientActionEvent(action, details));
  }

  @override
  Future<void> interruptAgentResponse({required String reason}) async {
    if (!isActive) return;
    _audioPlaybackEnabled = false;
    _discardInterruptedOutput = true;
    _emit(VoiceAgentInterruptedEvent(reason: reason));
    await _audioPlayer.interrupt();
  }

  @override
  Future<VoiceExpenseCommandResult> stop() async {
    if (_explicitlyStopped) {
      return const VoiceExpenseCommandResult(message: 'Session ended.');
    }
    recordClientEvent('end_session');
    _explicitlyStopped = true;
    _active = false;
    _reconnectTimer?.cancel();
    _goAwayTimer?.cancel();
    await _closeSocket(invalidateGeneration: true);
    await _audioPlayer.stop();
    final summary =
        'Sent $_inputChunks input chunks, received $_outputAudioChunks audio '
        'chunks ($_outputAudioBytes bytes).';
    _emit(VoiceSystemEvent(summary));
    _recordSessionCostMetric();
    final sessionId = _sessionId;
    if (sessionId != null) await sessionRepository.endExplicitly(sessionId);
    await sessionRepository.flush();
    await remoteSync?.flush();
    onEnded();
    return VoiceExpenseCommandResult(message: summary);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    _reconnectTimer?.cancel();
    _goAwayTimer?.cancel();
    await _closeSocket(invalidateGeneration: true);
    await _audioPlayer.stop();
    final sessionId = _sessionId;
    if (!_explicitlyStopped && sessionId != null) {
      _recordSessionCostMetric();
      await sessionRepository.markStatus(sessionId, 'suspended');
    }
    await sessionRepository.flush();
    await _events.close();
    onEnded();
  }

  void _handleServerMessage(dynamic rawMessage, int generation) {
    if (generation != _connectionGeneration || !isActive) return;
    final text = rawMessage is String
        ? rawMessage
        : rawMessage is List<int>
        ? utf8.decode(rawMessage)
        : rawMessage.toString();

    Map<String, dynamic> message;
    try {
      message = (jsonDecode(text) as Map).cast<String, dynamic>();
    } catch (error) {
      _emit(VoiceErrorEvent('Malformed Gemini message: $error'));
      _persistProtocolEvent(
        type: 'malformed_server_message',
        direction: 'server',
        payload: {'text': text, 'error': error.toString()},
      );
      return;
    }
    _persistProtocolEvent(
      type: 'server_message',
      direction: 'server',
      payload: const {},
      raw: _withoutInlineBinary(message),
    );

    final usage = message['usageMetadata'];
    if (usage is Map) {
      final metadata = usage.cast<String, Object?>();
      _latestUsageMetadata = metadata;
      _recordInteractionCostMetric(metadata);
      _emit(VoiceUsageMetadataEvent(metadata));
    }

    final resumption = message['sessionResumptionUpdate'];
    if (resumption is Map) _handleResumptionUpdate(resumption);

    final goAway = message['goAway'];
    if (goAway is Map) _handleGoAway(goAway);

    if (message.containsKey('setupComplete')) {
      final completer = _setupComplete;
      if (completer != null && !completer.isCompleted) completer.complete();
    }

    final cancellation = message['toolCallCancellation'];
    if (cancellation is Map) _handleToolCancellation(cancellation);

    final toolCall = message['toolCall'];
    if (toolCall is Map) {
      unawaited(_handleToolCall(toolCall.cast<String, dynamic>()));
    }

    final serverContent = message['serverContent'];
    if (serverContent is Map) {
      _handleServerContent(serverContent.cast<String, dynamic>());
    }
  }

  void _handleResumptionUpdate(Map<dynamic, dynamic> update) {
    final resumable = update['resumable'] == true;
    final handle = update['newHandle'];
    final hasHandle = resumable && handle is String && handle.isNotEmpty;
    _emit(
      VoiceSessionResumptionEvent(
        resumable: resumable,
        hasNewHandle: hasHandle,
      ),
    );
    if (!hasHandle) return;
    _resumeHandle = handle;
    final sessionId = _sessionId;
    if (sessionId != null) {
      unawaited(
        sessionRepository
            .updateResumeHandle(
              sessionId: sessionId,
              handle: handle,
              at: DateTime.now(),
            )
            .then((_) => remoteSync?.schedule()),
      );
    }
  }

  void _handleGoAway(Map<dynamic, dynamic> goAway) {
    final timeLeft = goAway['timeLeft']?.toString();
    _emit(VoiceGoAwayEvent(timeLeft));
    _goAwayTimer?.cancel();
    if (_resumeHandle == null) return;
    final remaining =
        _parseGoogleDuration(timeLeft) ?? const Duration(seconds: 5);
    final delay = remaining > const Duration(seconds: 2)
        ? remaining - const Duration(seconds: 2)
        : const Duration(milliseconds: 100);
    _goAwayTimer = Timer(delay, () {
      if (isActive) unawaited(_reconnectNow('goAway'));
    });
  }

  void _handleToolCancellation(Map<dynamic, dynamic> cancellation) {
    final ids = cancellation['ids'];
    final idList = ids is List
        ? ids.map((value) => value.toString()).toList(growable: false)
        : <String>[];
    _cancelledToolIds.addAll(idList);
    _emit(VoiceToolCancelledEvent(idList));
  }

  void _handleServerContent(Map<String, dynamic> serverContent) {
    final inputTranscription = serverContent['inputTranscription'];
    if (inputTranscription is Map) {
      final text = inputTranscription['text'];
      if (text is String && text.isNotEmpty) {
        if (_screenAttached) {
          _audioPlaybackEnabled = true;
          _discardInterruptedOutput = false;
        }
        _emit(VoiceUserTranscriptDelta(text));
      }
    }

    final outputTranscription = serverContent['outputTranscription'];
    if (outputTranscription is Map) {
      final text = outputTranscription['text'];
      if (text is String && text.isNotEmpty) {
        _emit(VoiceAgentTranscriptDelta(text));
      }
    }

    if (serverContent['interrupted'] == true) {
      _discardInterruptedOutput = true;
      _emit(VoiceAgentInterruptedEvent());
      unawaited(_audioPlayer.interrupt());
    }

    final modelTurn = serverContent['modelTurn'];
    if (modelTurn is Map) {
      final parts = modelTurn['parts'];
      if (parts is List) {
        for (final part in parts) {
          if (part is! Map) continue;
          final text = part['text'];
          if (text is String && text.isNotEmpty) {
            _emit(VoiceAgentTranscriptDelta(text));
          }
          final inlineData = part['inlineData'];
          if (inlineData is! Map) continue;
          final data = inlineData['data'];
          if (data is! String) continue;
          final pcmBytes = base64Decode(data);
          _outputAudioChunks += 1;
          _outputAudioBytes += pcmBytes.length;
          _persistProtocolEvent(
            type: 'audio_output_chunk',
            direction: 'server',
            modality: 'audio',
            payload: {
              'chunk': _outputAudioChunks,
              'byteLength': pcmBytes.length,
            },
            binaryData: pcmBytes,
            binaryMimeType:
                inlineData['mimeType']?.toString() ?? 'audio/pcm;rate=24000',
          );
          if (_audioPlaybackEnabled && !_discardInterruptedOutput) {
            unawaited(_audioPlayer.enqueue(pcmBytes));
          }
        }
      }
    }

    if (serverContent['turnComplete'] == true) {
      _discardInterruptedOutput = false;
      _emit(VoiceAgentTurnComplete());
    }
  }

  Future<void> _handleToolCall(Map<String, dynamic> toolCall) async {
    final calls = toolCall['functionCalls'];
    if (calls is! List) return;
    final responses = <Map<String, dynamic>>[];
    for (final call in calls) {
      if (call is! Map) continue;
      final id = call['id']?.toString() ?? '';
      final name = call['name']?.toString() ?? '';
      final rawArgs = call['args'];
      final args = rawArgs is Map
          ? rawArgs.cast<String, dynamic>()
          : <String, dynamic>{};
      _emit(VoiceToolCallEvent(id: id, name: name, args: args));
      _toolCallSinceLastUsage = true;
      if (_cancelledToolIds.contains(id)) continue;

      final result = await _executors.execute(name, args);
      if (_cancelledToolIds.contains(id) || !isActive) continue;
      _emit(VoiceToolResultEvent(id: id, name: name, result: result));
      responses.add({
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'response': {'result': result},
      });
    }
    if (responses.isNotEmpty) {
      _sendOrQueue({
        'toolResponse': {'functionResponses': responses},
      });
    }
  }

  void _sendOrQueue(Map<String, dynamic> message) {
    _persistProtocolEvent(
      type: 'client_message',
      direction: 'client',
      payload: const {},
      raw: _withoutInlineBinary(message),
    );
    if (_connected && _channel != null) {
      _sendNow(message, persist: false);
      return;
    }
    if (_pendingMessages.length >= _maxQueuedMessages) {
      _pendingMessages.removeAt(0);
      _emit(VoiceSystemEvent('Dropped oldest queued message during reconnect'));
    }
    _pendingMessages.add(message);
  }

  void _sendNow(Map<String, dynamic> message, {bool persist = true}) {
    if (persist) {
      _persistProtocolEvent(
        type: 'client_message',
        direction: 'client',
        payload: const {},
        raw: _withoutInlineBinary(message),
      );
    }
    _channel?.sink.add(jsonEncode(message));
  }

  void _flushPendingMessages() {
    if (!_connected || _channel == null) return;
    final pending = List<Map<String, dynamic>>.of(_pendingMessages);
    _pendingMessages.clear();
    for (final message in pending) {
      _sendNow(message, persist: false);
    }
  }

  void _handleSocketDone(WebSocketChannel channel, int generation) {
    if (generation != _connectionGeneration) return;
    _connected = false;
    final completer = _setupComplete;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        StateError('Gemini disconnected before setup completed'),
      );
    }
    _emit(
      VoiceDisconnectedEvent(
        code: channel.closeCode,
        reason: channel.closeReason,
      ),
    );
    if (isActive) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!isActive || _reconnectTimer?.isActive == true) return;
    _reconnectAttempt += 1;
    final seconds = math.min(30, math.pow(2, _reconnectAttempt - 1).toInt());
    _emit(VoiceConnectingEvent('Reconnecting to Gemini Live in ${seconds}s'));
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!isActive) return;
      unawaited(
        _reconnectNow('socket_closed').catchError((Object error) {
          _emit(VoiceErrorEvent('Reconnect failed: $error', isTransient: true));
          _scheduleReconnect();
        }),
      );
    });
  }

  Future<void> _reconnectNow(String reason) async {
    if (!isActive) return;
    _reconnectTimer?.cancel();
    _goAwayTimer?.cancel();
    _emit(VoiceConnectingEvent('Reconnecting to Gemini Live ($reason)'));
    await _closeSocket(invalidateGeneration: true);
    await _connect();
  }

  void _recordSessionCostMetric() {
    if (_sessionCostMetricSent) return;
    final usage = _latestUsageMetadata;
    final sessionId = _sessionId;
    if (usage == null || sessionId == null) return;
    _sessionCostMetricSent = true;
    agentMetrics?.recordSessionCostFromUsageBestEffort(
      sessionId: sessionId,
      model: _model,
      mode: _sessionMode(),
      usage: usage,
    );
  }

  void _recordInteractionCostMetric(Map<String, Object?> usage) {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final metrics = agentMetrics;
    if (metrics == null) return;
    final totalCostUsd = metrics.estimateSessionCostUsd(usage);
    if (totalCostUsd == null) return;
    final previousTotalCostUsd = _lastInteractionTotalCostUsd;
    if (totalCostUsd == previousTotalCostUsd) return;
    final interactionCostUsd =
        previousTotalCostUsd == null || totalCostUsd < previousTotalCostUsd
        ? totalCostUsd
        : totalCostUsd - previousTotalCostUsd;
    _lastInteractionTotalCostUsd = totalCostUsd;
    if (interactionCostUsd <= 0) return;
    final interactionType = _interactionType();
    _interactionSequence += 1;
    final sampleId = '$sessionId:$_interactionSequence';
    _toolCallSinceLastUsage = false;
    metrics.recordInteractionCostBestEffort(
      sessionId: sessionId,
      sampleId: sampleId,
      model: _model,
      mode: _sessionMode(),
      interactionType: interactionType,
      costUsd: interactionCostUsd,
    );
  }

  String _interactionType() {
    if (_toolCallSinceLastUsage) return 'tool';
    return _sessionMode();
  }

  String _sessionMode() {
    if (_inputChunks > 0 && _textMessages > 0) return 'mixed';
    if (_inputChunks > 0) return 'voice';
    return 'text';
  }

  Future<void> _closeSocket({required bool invalidateGeneration}) async {
    if (invalidateGeneration) _connectionGeneration += 1;
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    _connected = false;
    await subscription?.cancel();
    await channel?.sink.close();
  }

  void _emit(VoiceEvent event) {
    _history.add(event);
    if (!_events.isClosed) _events.add(event);
    final record = _eventRecord(event);
    _persistProtocolEvent(
      type: record.type,
      direction: record.direction,
      modality: record.modality,
      payload: record.payload,
      occurredAt: event.at,
    );
  }

  void _persistProtocolEvent({
    required String type,
    required String direction,
    String? modality,
    Map<String, Object?> payload = const {},
    Map<String, Object?>? raw,
    Uint8List? binaryData,
    String? binaryMimeType,
    DateTime? occurredAt,
  }) {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    unawaited(
      sessionRepository
          .appendEvent(
            sessionId: sessionId,
            occurredAt: occurredAt ?? DateTime.now(),
            type: type,
            direction: direction,
            modality: modality,
            payload: payload,
            raw: raw,
            binaryData: binaryData,
            binaryMimeType: binaryMimeType,
          )
          .then((_) => remoteSync?.schedule()),
    );
  }

  _VoiceEventRecord _eventRecord(VoiceEvent event) => switch (event) {
    VoiceConnectingEvent(:final message) => _VoiceEventRecord(
      'connecting',
      'local',
      {'message': message},
    ),
    VoiceConnectedEvent() => const _VoiceEventRecord('connected', 'local', {}),
    VoiceDisconnectedEvent(:final code, :final reason) => _VoiceEventRecord(
      'disconnected',
      'server',
      {'code': ?code, 'reason': ?reason},
    ),
    VoiceErrorEvent(:final message, :final isTransient) => _VoiceEventRecord(
      'error',
      'local',
      {'message': message, 'isTransient': isTransient},
    ),
    VoiceSystemEvent(:final message) => _VoiceEventRecord('system', 'local', {
      'message': message,
    }),
    VoiceClientActionEvent(:final action, :final details) => _VoiceEventRecord(
      action,
      'client',
      details,
      modality: details['interactionModality']?.toString(),
    ),
    VoiceSessionResumptionEvent(:final resumable, :final hasNewHandle) =>
      _VoiceEventRecord('session_resumption_update', 'server', {
        'resumable': resumable,
        'hasNewHandle': hasNewHandle,
      }),
    VoiceGoAwayEvent(:final timeLeft) => _VoiceEventRecord(
      'go_away',
      'server',
      {'timeLeft': ?timeLeft},
    ),
    VoiceUsageMetadataEvent(:final metadata) => _VoiceEventRecord(
      'usage_metadata',
      'server',
      metadata,
    ),
    VoiceUserTranscriptDelta(:final text) => _VoiceEventRecord(
      'user_transcript_delta',
      'server',
      {'text': text},
      modality: 'voice',
    ),
    VoiceAgentTranscriptDelta(:final text) => _VoiceEventRecord(
      'agent_transcript_delta',
      'server',
      {'text': text},
      modality: 'voice',
    ),
    VoiceAgentTurnComplete() => const _VoiceEventRecord(
      'agent_turn_complete',
      'server',
      {},
    ),
    VoiceAgentInterruptedEvent(:final reason) => _VoiceEventRecord(
      'agent_interrupted',
      reason == 'server_interrupted' ? 'server' : 'client',
      {'reason': reason},
    ),
    VoiceToolCallEvent(:final id, :final name, :final args) =>
      _VoiceEventRecord('tool_call', 'server', {
        'id': id,
        'name': name,
        'args': args,
      }, modality: 'tool'),
    VoiceToolResultEvent(:final id, :final name, :final result) =>
      _VoiceEventRecord('tool_result', 'client', {
        'id': id,
        'name': name,
        'result': result,
      }, modality: 'tool'),
    VoiceToolCancelledEvent(:final ids) => _VoiceEventRecord(
      'tool_cancelled',
      'server',
      {'ids': ids},
      modality: 'tool',
    ),
  };

  Map<String, Object?> _withoutInlineBinary(Map<dynamic, dynamic> value) {
    Object? clean(Object? node) {
      if (node is List) return node.map(clean).toList(growable: false);
      if (node is! Map) return node;
      final mimeType = node['mimeType']?.toString();
      return <String, Object?>{
        for (final entry in node.entries)
          entry.key.toString():
              entry.key == 'data' &&
                  mimeType != null &&
                  mimeType.startsWith('audio/')
              ? '<stored in binary event>'
              : clean(entry.value),
      };
    }

    return (clean(value) as Map).cast<String, Object?>();
  }

  Duration? _parseGoogleDuration(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^([0-9]+(?:\.[0-9]+)?)s$').firstMatch(value);
    if (match == null) return null;
    final seconds = double.tryParse(match.group(1)!);
    if (seconds == null) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }
}

class _VoiceEventRecord {
  const _VoiceEventRecord(
    this.type,
    this.direction,
    this.payload, {
    this.modality,
  });

  final String type;
  final String direction;
  final Map<String, Object?> payload;
  final String? modality;
}
