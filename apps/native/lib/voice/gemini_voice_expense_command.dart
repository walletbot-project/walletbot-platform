import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../convex/convex_client.dart';
import '../data/data.dart';
import '../fx/fx_rates_controller.dart';
import '../settings/display_settings.dart';
import '../telemetry/agent_interaction_cost_tracker.dart';
import '../telemetry/agent_metrics.dart';
import '../user_settings/default_currency_controller.dart';
import 'agent_generated.dart';
import 'live_token_provider.dart';
import 'live_connection.dart';
import 'live_protocol.dart';
import 'live_tool_dispatcher.dart';
export 'live_token_provider.dart'
    show LiveTokenRefusedException, MissingLiveCredentialsException;
import 'pcm_audio_player.dart';
import 'tool_executors.dart';
import 'voice_event.dart';
import 'voice_event_log.dart';
import 'voice_expense_command.dart';
import 'voice_session_remote_sync.dart';
import 'voice_session_repository.dart';
export 'gemini_voice_command_factory.dart';

class GeminiVoiceExpenseCommand implements VoiceExpenseCommand {
  GeminiVoiceExpenseCommand({
    required this.repositories,
    required this.sessionRepository,
    required this.remoteSync,
    required this.agentMetrics,
    required this.useAuthenticatedTokenAction,
    required this.sessionToken,
    required this.deviceId,
    required this.convexClient,
    required this.liveToken,
    required this.convexSiteUrl,
    required this.onEnded,
    this.buildMintArgs,
    this.takePrefetchedToken,
    DisplaySettingsController? displaySettings,
    DefaultCurrencyController? defaultCurrency,
    FxRatesController? fxRates,
  }) : _executors = ToolExecutors(
         repositories,
         displaySettings: displaySettings,
         defaultCurrency: defaultCurrency,
         fxQuotes: fxRates == null ? null : () => fxRates.quotes,
       );

  String get _model => _connection.model ?? kAgentModel;
  static const _maxQueuedMessages = 20;

  final AppRepositories repositories;
  final VoiceSessionRepository sessionRepository;
  final VoiceSessionRemoteSync? remoteSync;
  final AgentMetrics? agentMetrics;
  final bool useAuthenticatedTokenAction;
  final String? sessionToken;
  final String? deviceId;
  final ConvexClient? convexClient;
  final String liveToken;
  final String convexSiteUrl;
  final void Function() onEnded;

  /// See [GeminiVoiceExpenseCommandFactory.buildMintArgs].
  final Future<Map<String, Object?>> Function()? buildMintArgs;

  /// Consumes the factory's screen-open token prefetch, when one is still
  /// inside the token's new-session window. Null result → fetch fresh.
  final Future<LiveToken>? Function()? takePrefetchedToken;
  final ToolExecutors _executors;
  final _audioPlayer = PcmAudioPlayer();
  final _events = StreamController<VoiceEvent>.broadcast();
  final List<VoiceEvent> _history = [];
  final List<Map<String, dynamic>> _pendingMessages = [];
  late final LiveConnection _connection = LiveConnection(
    credentials: () async {
      final prefetched = _prefetchedToken ?? takePrefetchedToken?.call();
      _prefetchedToken = null;
      final token = await (prefetched ?? _resolveLiveToken());
      if (token.isEmpty) {
        throw const MissingLiveCredentialsException();
      }
      return token;
    },
    beforeReady: () async {
      // A write that already started can finish after a disconnect. Seed its
      // committed result before admitting new work on the replacement socket.
      await _tools.settled;
      await sessionRepository.flush();
      final id = _sessionId;
      if (id != null) {
        await sessionRepository.updateModel(id, _model);
        if (!_sessionStartedMetricSent && isActive) {
          _sessionStartedMetricSent = true;
          // The backend's rollback flag chooses the actual model at token mint.
          // Opening the local session earlier only knows the compiled default.
          agentMetrics?.recordSessionStartedBestEffort(
            sessionId: id,
            model: _model,
            resumed: _sessionStartResumed,
          );
        }
      }
      return _buildContextSeed();
    },
    onMessage: _handleServerMessage,
    onMessageError: (error) =>
        _emit(VoiceErrorEvent('Live message handling failed: $error')),
    onSend: (message) => _persistProtocolEvent(
      type: 'client_message',
      direction: 'client',
      raw: withoutInlineBinary(message),
    ),
    onState: (state) {
      if (state == LiveConnectionState.ready) {
        _emit(VoiceConnectedEvent());
        final id = _sessionId;
        if (id != null) unawaited(sessionRepository.markStatus(id, 'active'));
        _flushPendingMessages();
      } else if (state == LiveConnectionState.reconnecting) {
        _audioStreamOpen = false;
        _discardInterruptedOutput = false;
        unawaited(_flushPlayback());
        _emit(VoiceDisconnectedEvent());
        _emit(VoiceConnectingEvent('Reconnecting to Gemini Live'));
      }
    },
    onError: (error) {
      final permanent =
          error is LiveTokenRefusedException ||
          error is MissingLiveCredentialsException;
      _emit(
        VoiceErrorEvent(
          '$error',
          isTransient: !permanent,
          code: error is LiveTokenRefusedException ? error.reason : null,
        ),
      );
      if (permanent) unawaited(stop());
    },
  );
  late final LiveToolDispatcher _tools = LiveToolDispatcher(
    execute: _executors.execute,
    isCurrent: (epoch) =>
        isActive && _connection.ready && _connection.isCurrent(epoch),
    onCall: (id, name, args) {
      _emit(VoiceToolCallEvent(id: id, name: name, args: args));
      _interactionCostTracker.markToolCall();
    },
    onResult: (id, name, result) =>
        _emit(VoiceToolResultEvent(id: id, name: name, result: result)),
    respond: (response, epoch) =>
        _connection.send(response, expectedEpoch: epoch),
  );

  String? _sessionId;
  bool _sessionStartedMetricSent = false;
  bool _sessionStartResumed = false;
  Future<LiveToken>? _prefetchedToken;
  Future<void>? _starting;
  bool _active = false;
  bool _disposed = false;
  bool _explicitlyStopped = false;
  bool _audioPlaybackEnabled = true;
  bool _mutedByDetach = false;
  bool _screenAttached = false;
  bool _discardInterruptedOutput = false;
  bool _audioStreamOpen = false;
  int _playbackEpoch = 0;
  int _inputChunks = 0;
  int _textMessages = 0;
  int _outputAudioChunks = 0;
  int _outputAudioBytes = 0;
  bool _sessionCostMetricSent = false;
  final AgentInteractionCostTracker _interactionCostTracker =
      AgentInteractionCostTracker();

  @override
  String get label => 'Gemini Live voice expense command';

  @override
  String? get sessionId => _sessionId;

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  List<VoiceEvent> get history => List.unmodifiable(_history);

  @override
  bool get isActive => _active && !_explicitlyStopped && !_disposed;

  @override
  bool get isConnected => _connection.ready;

  @override
  Future<void> start({bool respondWithAudio = true}) {
    if (_starting != null) return _starting!;
    final operation = _start(respondWithAudio);
    _starting = operation;
    return operation.whenComplete(() {
      if (identical(_starting, operation)) _starting = null;
    });
  }

  Future<void> _start(bool respondWithAudio) async {
    _audioPlaybackEnabled = respondWithAudio;
    _mutedByDetach = false;
    if (isActive) {
      await ensureConnected();
      return;
    }
    if (_disposed || _explicitlyStopped) {
      throw StateError('Voice command has ended');
    }
    _active = true;

    final startStopwatch = Stopwatch()..start();
    final session = await sessionRepository.openOrCreate(model: _model);
    _sessionId = session.id;
    if (!isActive) {
      if (_explicitlyStopped) {
        await sessionRepository.endExplicitly(session.id);
      } else {
        await sessionRepository.markStatus(session.id, 'suspended');
      }
      return;
    }
    remoteSync?.schedule(delay: Duration.zero);
    final resumed = session.resumeHandle != null;
    _logConnectionPhase('session_opened', startStopwatch, {'resumed': resumed});
    _sessionStartResumed = resumed;

    _emit(VoiceConnectingEvent('Connecting to Gemini Live'));
    // The token fetch and the audio engine spin-up are independent and each
    // can take hundreds of milliseconds — overlap them. `_connectOnce`
    // consumes the prefetched future (or fetches fresh on reconnects).
    // Prefer a fetch the factory already started when the screen opened.
    final tokenFetch = takePrefetchedToken?.call() ?? _resolveLiveToken();
    tokenFetch.ignore();
    _prefetchedToken = tokenFetch;
    if (respondWithAudio) await prepareAudio();
    if (isActive) await _connection.connect();
  }

  @override
  Future<void> ensureConnected() async {
    if (isActive) await _connection.connect();
  }

  @override
  Future<void> prepareAudio() async {
    if (!isActive) return;
    final diagnostics = await _audioPlayer.start(
      sampleRate: LiveProtocol.outputRate,
    );
    if (diagnostics != null && isActive) {
      _emit(VoiceSystemEvent('Voice engine: $diagnostics'));
    }
  }

  /// Transcript seed for the fresh server session this connect just opened —
  /// [buildConversationSeed] over the durable log of the session being
  /// continued. Null when there is no prior conversation to restore.
  Future<String?> _buildContextSeed() async {
    try {
      final rows = await sessionRepository.resumableConversationEvents(
        types: kConversationEventTypes,
      );
      if (rows.isEmpty) return null;
      final events = <VoiceEvent>[];
      for (final row in rows) {
        final decoded = jsonDecode(row.payloadJson);
        if (decoded is! Map) continue;
        final event = voiceEventFromRecord(
          type: row.type,
          payload: decoded.cast<String, Object?>(),
          at: DateTime.fromMillisecondsSinceEpoch(row.occurredAt.toInt()),
        );
        if (event != null) events.add(event);
      }
      final pendingTexts = <String>[];
      for (final message in _pendingMessages) {
        final content = message['clientContent'];
        if (content is! Map) continue;
        final turns = content['turns'];
        if (turns is! List || turns.isEmpty) continue;
        final firstTurn = turns.first;
        if (firstTurn is! Map) continue;
        final parts = firstTurn['parts'];
        if (parts is! List || parts.isEmpty) continue;
        final firstPart = parts.first;
        if (firstPart is Map) {
          final text = firstPart['text'];
          if (text is String && text.isNotEmpty) pendingTexts.add(text);
        }
      }
      return buildConversationSeed(events, pendingTexts: pendingTexts);
    } catch (error) {
      // A failed restore must never block the connection itself.
      debugPrint('[voice] context seed failed: $error');
      return null;
    }
  }

  /// Fetches a fresh single-use token. The backend mints tokens with
  /// `uses: 1` and a short new-session window, so a token can never be
  /// reused across connection attempts — every (re)connect resolves a new
  /// one, and nothing is cached.
  Future<LiveToken> _resolveLiveToken() async {
    if (liveToken.isNotEmpty) return LiveToken(liveToken);
    _emit(VoiceSystemEvent('Requesting live token from Convex'));
    final token = await fetchLiveToken(
      useAuthenticatedTokenAction: useAuthenticatedTokenAction,
      convexClient: convexClient,
      sessionToken: sessionToken,
      deviceId: deviceId,
      convexSiteUrl: convexSiteUrl,
      buildMintArgs: buildMintArgs,
      onPhase: (phase, extra) {
        if (phase == 'token_action_failed') {
          _emit(
            VoiceSystemEvent(
              'Authenticated token action failed: ${extra['error']}',
            ),
          );
        }
        _logPhaseRecord(phase, extra);
      },
    );
    if (token.isNotEmpty) {
      _emit(VoiceSystemEvent('Live token received'));
    }
    return token;
  }

  /// Persists a timestamped connection-phase marker to the durable session
  /// log (and the debug console) so slow connects are diagnosable from an
  /// exported session without a console attached.
  void _logConnectionPhase(
    String phase,
    Stopwatch stopwatch, [
    Map<String, Object?> extra = const {},
  ]) {
    _logPhaseRecord(phase, {
      'elapsedMs': stopwatch.elapsedMilliseconds,
      ...extra,
    });
  }

  void _logPhaseRecord(String phase, Map<String, Object?> payload) {
    final record = <String, Object?>{'phase': phase, ...payload};
    debugPrint('[voice] connection phase: $record');
    _persistProtocolEvent(
      type: 'connection_phase',
      direction: 'local',
      payload: record,
    );
  }

  @override
  Future<void> addAudioChunk(Uint8List chunk) async {
    if (!isActive || !isConnected || chunk.isEmpty) return;
    if (chunk.length.isOdd) {
      throw const FormatException('Unaligned microphone PCM16');
    }
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
    _connection.send(LiveProtocol.audio(chunk));
  }

  @override
  Future<void> endAudioStream() async {
    if (!isActive || !_audioStreamOpen) return;
    _audioStreamOpen = false;
    _connection.send({
      'realtimeInput': {'audioStreamEnd': true},
    });
  }

  @override
  void setAudioPlaybackEnabled(bool enabled) {
    _mutedByDetach = false;
    if (_audioPlaybackEnabled == enabled) return;
    _audioPlaybackEnabled = enabled;
    recordClientEvent('audio_playback_changed', {'enabled': enabled});
    if (!enabled) unawaited(_flushPlayback());
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
    await _flushPlayback();
    _discardInterruptedOutput = false;
    _sendOrQueue(LiveProtocol.text(trimmed));
  }

  @override
  void recordClientEvent(
    String action, [
    Map<String, Object?> details = const {},
  ]) {
    if (!isActive) return;
    if (action == 'screen_attached') {
      _screenAttached = true;
      // The screen's dispose mutes playback so a closed screen never plays
      // audio. Undo that mute on re-entry — unless something explicit (a
      // typed turn, a new start) set playback in the meantime.
      if (_mutedByDetach) {
        _mutedByDetach = false;
        _audioPlaybackEnabled = true;
      }
    }
    if (action == 'screen_detached') {
      _screenAttached = false;
      _mutedByDetach = _audioPlaybackEnabled;
    }
    _emit(VoiceClientActionEvent(action, details: details));
  }

  @override
  Future<void> interruptAgentResponse({required String reason}) async {
    if (!isActive) return;
    _audioPlaybackEnabled = false;
    _discardInterruptedOutput = true;
    final suspend = reason == 'screen_detached' || reason == 'app_backgrounded';
    if (suspend) {
      recordClientEvent('audio_suspended', {'reason': reason});
    } else {
      _emit(VoiceAgentInterruptedEvent(reason: reason));
    }
    await _flushPlayback();
    if (suspend) {
      await _audioPlayer.stop();
    }
  }

  @override
  Future<VoiceExpenseCommandResult> stop() async {
    if (_explicitlyStopped) {
      return const VoiceExpenseCommandResult(message: 'Session ended.');
    }
    recordClientEvent('end_session');
    _explicitlyStopped = true;
    _active = false;
    _prefetchedToken = null;
    await _connection.close();
    _pendingMessages.clear();
    await _tools.settled;
    await _audioPlayer.stop();
    final summary =
        'Sent $_inputChunks input chunks, received $_outputAudioChunks audio '
        'chunks ($_outputAudioBytes bytes).';
    _emit(VoiceSystemEvent(summary));
    _recordSessionCostMetric();
    final sessionId = _sessionId;
    if (sessionId != null) await sessionRepository.endExplicitly(sessionId);
    await sessionRepository.flush();
    // Best-effort replication: offline this can sit on the Convex client's
    // 30 s operation timeout, and ending the conversation must never wait on
    // it. Unsynced rows stay in the durable outbox and retry later.
    unawaited(remoteSync?.flush());
    _emit(VoiceDisconnectedEvent());
    onEnded();
    return VoiceExpenseCommandResult(message: summary);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _active = false;
    _prefetchedToken = null;
    await _connection.close();
    _pendingMessages.clear();
    await _tools.settled;
    await _audioPlayer.stop();
    final sessionId = _sessionId;
    if (!_explicitlyStopped && sessionId != null) {
      _recordSessionCostMetric();
      await sessionRepository.markStatus(sessionId, 'suspended');
    }
    await sessionRepository.flush();
    _disposed = true;
    await _events.close();
    onEnded();
  }

  void _handleServerMessage(Map<String, dynamic> message, int generation) {
    if (!_connection.isCurrent(generation) || !isActive) return;
    _persistProtocolEvent(
      type: 'server_message',
      direction: 'server',
      payload: const {},
      raw: withoutInlineBinary(message),
    );

    final usage = message['usageMetadata'];
    if (usage is Map) {
      final metadata = usage.cast<String, Object?>();
      _recordInteractionCostMetric(metadata);
      _emit(VoiceUsageMetadataEvent(metadata));
    }

    final resumption = message['sessionResumptionUpdate'];
    if (resumption is Map) _handleResumptionUpdate(resumption);

    final goAway = message['goAway'];
    if (goAway is Map) _handleGoAway(goAway);

    final cancellation = message['toolCallCancellation'];
    if (cancellation is Map) _handleToolCancellation(cancellation, generation);

    final toolCall = message['toolCall'];
    if (toolCall is Map) {
      unawaited(_tools.dispatch(toolCall.cast<String, dynamic>(), generation));
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
    // Handles are persisted for their freshness timestamp (the local
    // resumable-session gate), not to be presented on reconnect.
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
    _connection.rotateAfter(
      _parseGoogleDuration(timeLeft) ?? const Duration(seconds: 5),
    );
  }

  void _handleToolCancellation(
    Map<dynamic, dynamic> cancellation,
    int generation,
  ) {
    final ids = cancellation['ids'];
    final idList = ids is List
        ? ids.map((value) => value.toString()).toList(growable: false)
        : <String>[];
    _tools.cancel(idList, generation);
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
      _discardInterruptedOutput = false;
      _emit(VoiceAgentInterruptedEvent());
      unawaited(_flushPlayback());
    }

    final modelTurn = serverContent['modelTurn'];
    if (modelTurn is Map) {
      final parts = modelTurn['parts'];
      if (parts is List) {
        for (final part in parts) {
          if (part is! Map || part['thought'] == true) continue;
          final text = part['text'];
          if (text is String &&
              text.isNotEmpty &&
              outputTranscription is! Map) {
            _emit(VoiceAgentTranscriptDelta(text));
          }
          final Uint8List? pcmBytes;
          try {
            pcmBytes = LiveProtocol.pcm(part);
          } on FormatException catch (error) {
            _emit(VoiceErrorEvent('Ignored malformed audio: $error'));
            continue;
          }
          if (pcmBytes == null) continue;
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
            binaryMimeType: 'audio/pcm;rate=24000',
          );
          if (_audioPlaybackEnabled &&
              !_discardInterruptedOutput &&
              serverContent['interrupted'] != true) {
            unawaited(_playAudio(pcmBytes));
          }
        }
      }
    }

    if (serverContent['turnComplete'] == true) {
      _discardInterruptedOutput = false;
      _emit(VoiceAgentTurnComplete());
    }
  }

  Future<void> _playAudio(Uint8List bytes) async {
    final epoch = _playbackEpoch;
    try {
      await prepareAudio();
      if (!isActive || !_audioPlaybackEnabled || epoch != _playbackEpoch) {
        return;
      }
      await _audioPlayer.enqueue(bytes);
    } catch (error) {
      _emit(VoiceErrorEvent('Audio playback failed: $error'));
    }
  }

  Future<void> _flushPlayback() async {
    ++_playbackEpoch;
    try {
      await _audioPlayer.interrupt();
    } catch (error) {
      _emit(VoiceErrorEvent('Audio interruption failed: $error'));
    }
  }

  // Only intentional user text survives a reconnect. Replaying microphone
  // fragments or old tool responses produces stale turns and duplicate writes.
  void _sendOrQueue(Map<String, dynamic> message) {
    if (_connection.send(message)) return;
    if (_pendingMessages.length >= _maxQueuedMessages) {
      throw StateError('Too many pending messages; wait for the connection');
    }
    _pendingMessages.add(message);
  }

  void _flushPendingMessages() {
    while (_pendingMessages.isNotEmpty && _connection.ready) {
      if (!_connection.send(_pendingMessages.first)) return;
      _pendingMessages.removeAt(0);
    }
  }

  void _recordSessionCostMetric() {
    if (_sessionCostMetricSent) return;
    final sessionId = _sessionId;
    if (sessionId == null) return;
    _sessionCostMetricSent = true;
    for (final entry in _interactionCostTracker.totalsByModel.entries) {
      agentMetrics?.recordSessionCostBestEffort(
        sessionId: sessionId,
        model: entry.key,
        mode: _sessionMode(),
        costUsd: entry.value.costUsd,
        tokenAttributes: entry.value.tokens,
      );
    }
  }

  void _recordInteractionCostMetric(Map<String, Object?> usage) {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final metrics = agentMetrics;
    if (metrics == null) return;
    final generationCostUsd = metrics.estimateSessionCostUsd(usage);
    if (generationCostUsd == null) return;
    final sample = _interactionCostTracker.nextSample(
      sessionId: sessionId,
      model: _model,
      generationCostUsd: generationCostUsd,
      fallbackInteractionType: _sessionMode(),
      tokenAttributes: AgentMetrics.usageTokenAttributes(usage),
    );
    if (sample == null) return;
    metrics.recordInteractionCostBestEffort(
      sessionId: sessionId,
      sampleId: sample.sampleId,
      model: _model,
      mode: _sessionMode(),
      interactionType: sample.interactionType,
      costUsd: sample.costUsd,
      tokenAttributes: sample.tokenAttributes,
    );
  }

  String _sessionMode() {
    if (_inputChunks > 0 && _textMessages > 0) return 'mixed';
    if (_inputChunks > 0) return 'voice';
    return 'text';
  }

  void _emit(VoiceEvent event) {
    if (_disposed) return;
    _history.add(event);
    if (!_events.isClosed) _events.add(event);
    final record = voiceEventRecord(event);
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

  Duration? _parseGoogleDuration(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^([0-9]+(?:\.[0-9]+)?)s$').firstMatch(value);
    if (match == null) return null;
    final seconds = double.tryParse(match.group(1)!);
    if (seconds == null) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }
}
