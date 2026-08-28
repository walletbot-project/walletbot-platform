import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../convex/convex_client.dart';
import '../data/data.dart';
import '../fx/fx_rates_controller.dart';
import '../settings/display_settings.dart';
import '../telemetry/agent_interaction_cost_tracker.dart';
import '../telemetry/agent_metrics.dart';
import '../user_settings/default_currency_controller.dart';
import 'agent_generated.dart';
import 'pcm_audio_player.dart';
import 'tool_executors.dart';
import 'voice_event.dart';
import 'voice_expense_command.dart';
import 'voice_session_remote_sync.dart';
import 'voice_session_repository.dart';

/// One-shot fetch of a constrained Gemini Live token from the backend,
/// shared by the command's connect path and the factory's prefetch.
///
/// Nothing about starting a voice session waits on the Convex socket. The
/// action rides that socket, which can itself be mid-reconnect exactly when a
/// voice reconnect needs a token (network loss, resume from background), so
/// it is bounded to 6 s *and* runs as a one-shot HTTP POST whenever the
/// socket is not ready, rather than queueing behind the reconnect. The
/// `/v1/live/token` endpoint below is the last resort and is independent of
/// the Convex client entirely.
Future<String> _fetchLiveToken({
  required bool useAuthenticatedTokenAction,
  required ConvexClient? convexClient,
  required String? sessionToken,
  required String convexSiteUrl,
  Future<Map<String, Object?>> Function()? buildMintArgs,
  void Function(String phase, Map<String, Object?> extra)? onPhase,
}) async {
  final fetchStopwatch = Stopwatch()..start();
  // The mint args (platform identity, locale/timezone, USER_CONTEXT snapshot)
  // are best-effort: a failed build must never block the token fetch.
  Map<String, Object?> mintArgs = const {};
  if (buildMintArgs != null) {
    try {
      mintArgs = await buildMintArgs();
    } catch (e) {
      onPhase?.call('mint_args_failed', {
        'elapsedMs': fetchStopwatch.elapsedMilliseconds,
        'error': e.toString(),
      });
    }
  }
  Map<String, Object?>? body;
  var via = 'http_endpoint';
  if (useAuthenticatedTokenAction && convexClient != null) {
    final status = convexClient.currentConnectionState.status;
    final ready = status == ConnectionStatus.ready;
    onPhase?.call('token_action_start', {
      'elapsedMs': fetchStopwatch.elapsedMilliseconds,
      'connection': status.name,
      'transport': ready ? 'convex_ws' : 'convex_http',
    });
    try {
      final decoded = await convexClient.action<Object?>(
        'v1/live/actions:requestLiveToken',
        mintArgs,
        options: const CallOptions(
          operationTimeout: Duration(seconds: 6),
          httpFallback: HttpFallback.whenNotReady,
        ),
      );
      if (decoded is! Map) {
        throw StateError('Malformed Convex live token response');
      }
      body = decoded.cast<String, Object?>();
      via = ready ? 'convex_ws' : 'convex_http';
    } catch (error) {
      onPhase?.call('token_action_failed', {
        'elapsedMs': fetchStopwatch.elapsedMilliseconds,
        'connection': status.name,
        'error': error.toString(),
      });
    }
  }
  if (body == null) {
    if (convexSiteUrl.isEmpty) return '';
    final credential = sessionToken;
    if (credential == null || credential.isEmpty) return '';
    final base = Uri.parse(convexSiteUrl);
    final response = await http
        .post(
          base.replace(path: '/v1/live/token'),
          headers: {
            'Authorization': 'Bearer $credential',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(mintArgs),
        )
        .timeout(const Duration(seconds: 15));
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
  onPhase?.call('token_received', {
    'elapsedMs': fetchStopwatch.elapsedMilliseconds,
    // Which transport actually served it. A session that starts slowly is a
    // different bug depending on this: `convex_ws` points at the socket,
    // `http_endpoint` means the Convex action failed outright.
    'via': via,
    'model': body['model']?.toString(),
    // Server-reported breakdown (google round trip, mint total, cold-start
    // module age, action/http totals): elapsedMs minus the server total is
    // network + Convex routing.
    if (body['timings'] is Map) 'server': body['timings'],
  });
  return token;
}

class GeminiVoiceExpenseCommandFactory implements VoiceExpenseCommandFactory {
  GeminiVoiceExpenseCommandFactory({
    required this.repositories,
    required this.sessionRepository,
    this.remoteSync,
    this.agentMetrics,
    this.useAuthenticatedTokenAction = false,
    this.sessionToken,
    this.buildMintArgs,
    this.displaySettings,
    this.defaultCurrency,
    this.fxRates,
    this.convexClient,
    this.apiKey = const String.fromEnvironment('GEMINI_API_KEY'),
    this.liveToken = const String.fromEnvironment('GEMINI_LIVE_TOKEN'),
    this.convexSiteUrl = const String.fromEnvironment('CONVEX_SITE_URL'),
  });

  final AppRepositories repositories;
  final VoiceSessionRepository sessionRepository;
  final VoiceSessionRemoteSync? remoteSync;
  final AgentMetrics? agentMetrics;
  final bool useAuthenticatedTokenAction;
  final String? sessionToken;

  /// Builds the mint request (platform identity, locale/timezone and the
  /// USER_CONTEXT snapshot from Drift) — see `agent_context.dart`. Null keeps
  /// the bare mint of older builds.
  final Future<Map<String, Object?>> Function()? buildMintArgs;

  /// Controllers the `updateSettings` tool writes through, passed by
  /// reference at factory construction (main.dart): the app-scoped display
  /// settings and this account's default-currency controller.
  final DisplaySettingsController? displaySettings;
  final DefaultCurrencyController? defaultCurrency;

  /// Device-scoped exchange-rate cache the `getExchangeRate` tool reads.
  final FxRatesController? fxRates;

  /// Null when the app runs without a Convex transport (widget tests, and a
  /// local account without the authenticated action); the HTTP endpoint is
  /// the only token source then.
  final ConvexClient? convexClient;
  final String apiKey;
  final String liveToken;
  final String convexSiteUrl;
  GeminiVoiceExpenseCommand? _active;

  // Tokens are single-use with a 2-minute new-session window (see
  // packages/backend/convex/live/createToken.ts). The freshness bound stays
  // well inside that window so a consumed prefetch is always startable.
  static const _prefetchFreshness = Duration(seconds: 60);
  Future<String>? _prefetchedToken;
  DateTime? _prefetchedAt;

  @override
  VoiceExpenseCommand? get activeCommand {
    final active = _active;
    return active != null && active.isActive ? active : null;
  }

  @override
  void prefetchToken() {
    if (liveToken.isNotEmpty) return;
    final startedAt = _prefetchedAt;
    if (_prefetchedToken != null &&
        startedAt != null &&
        DateTime.now().difference(startedAt) < _prefetchFreshness) {
      return;
    }
    late final Future<String> future;
    future = _fetchLiveToken(
      useAuthenticatedTokenAction: useAuthenticatedTokenAction,
      convexClient: convexClient,
      sessionToken: sessionToken,
      convexSiteUrl: convexSiteUrl,
      buildMintArgs: buildMintArgs,
      onPhase: (phase, extra) =>
          debugPrint('[voice] token prefetch $phase: $extra'),
    );
    // A failed or credential-less prefetch must not poison the real connect:
    // drop it so takeFreshPrefetch hands out nothing and the command runs
    // its own fetch (with its own error surfacing).
    future.then(
      (token) {
        if (token.isEmpty && identical(_prefetchedToken, future)) {
          _prefetchedToken = null;
          _prefetchedAt = null;
        }
      },
      onError: (Object error) {
        debugPrint('[voice] token prefetch failed: $error');
        if (identical(_prefetchedToken, future)) {
          _prefetchedToken = null;
          _prefetchedAt = null;
        }
      },
    );
    _prefetchedToken = future;
    _prefetchedAt = DateTime.now();
  }

  /// Hands a still-fresh prefetched token fetch to a connecting command,
  /// consuming it. Null when none was started or it aged out of the token's
  /// new-session window.
  Future<String>? takeFreshPrefetch() {
    final future = _prefetchedToken;
    final startedAt = _prefetchedAt;
    _prefetchedToken = null;
    _prefetchedAt = null;
    if (future == null || startedAt == null) return null;
    if (DateTime.now().difference(startedAt) >= _prefetchFreshness) {
      return null;
    }
    return future;
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
      buildMintArgs: buildMintArgs,
      displaySettings: displaySettings,
      defaultCurrency: defaultCurrency,
      fxRates: fxRates,
      convexClient: convexClient,
      apiKey: apiKey,
      liveToken: liveToken,
      convexSiteUrl: convexSiteUrl,
      takePrefetchedToken: takeFreshPrefetch,
      onEnded: () {
        if (identical(_active, command)) _active = null;
      },
    );
    _active = command;
    return command;
  }

  @override
  Future<List<VoiceEvent>> restorableHistory() async {
    final rows = await sessionRepository.resumableConversationEvents(
      types: kConversationEventTypes,
    );
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
    return events;
  }

  @override
  Future<void> discardRestorableSession() async {
    await sessionRepository.endResumableSession();
    remoteSync?.schedule();
  }

  @override
  Future<String?> restorableSessionId() =>
      sessionRepository.resumableSessionId();

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

  // Model + voice come from the generated shared constants
  // (agent_generated.dart ← packages/shared/src/tools/constants.ts), the same
  // source the backend mint uses — a bump there can no longer desync native's
  // setup frame from the token's constraints (defect D4).
  static const _model = kAgentModel;
  static const _voiceName = kAgentVoiceName;
  static const _maxQueuedMessages = 200;

  final AppRepositories repositories;
  final VoiceSessionRepository sessionRepository;
  final VoiceSessionRemoteSync? remoteSync;
  final AgentMetrics? agentMetrics;
  final bool useAuthenticatedTokenAction;
  final String? sessionToken;
  final ConvexClient? convexClient;
  final String apiKey;
  final String liveToken;
  final String convexSiteUrl;
  final void Function() onEnded;

  /// See [GeminiVoiceExpenseCommandFactory.buildMintArgs].
  final Future<Map<String, Object?>> Function()? buildMintArgs;

  /// Consumes the factory's screen-open token prefetch, when one is still
  /// inside the token's new-session window. Null result → fetch fresh.
  final Future<String>? Function()? takePrefetchedToken;
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
  Future<String>? _prefetchedToken;
  bool _active = false;
  bool _connected = false;
  bool _disposed = false;
  bool _explicitlyStopped = false;
  bool _audioPlaybackEnabled = true;
  bool _mutedByDetach = false;
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
  final AgentInteractionCostTracker _interactionCostTracker =
      AgentInteractionCostTracker();
  Map<String, Object?>? _latestUsageMetadata;

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
  bool get isConnected => _connected;

  @override
  Future<void> start({bool respondWithAudio = true}) async {
    _audioPlaybackEnabled = respondWithAudio;
    _mutedByDetach = false;
    if (isActive) {
      await ensureConnected();
      return;
    }
    if (_disposed) throw StateError('Voice command is disposed');

    final startStopwatch = Stopwatch()..start();
    final session = await sessionRepository.openOrCreate(model: _model);
    _sessionId = session.id;
    _active = true;
    _explicitlyStopped = false;
    remoteSync?.schedule(delay: Duration.zero);
    _logConnectionPhase('session_opened', startStopwatch, {
      'resumed': session.resumeHandle != null,
    });

    _emit(VoiceConnectingEvent('Connecting to Gemini Live'));
    // The token fetch and the audio engine spin-up are independent and each
    // can take hundreds of milliseconds — overlap them. `_connectOnce`
    // consumes the prefetched future (or fetches fresh on reconnects).
    // Prefer a fetch the factory already started when the screen opened.
    final tokenFetch = takePrefetchedToken?.call() ?? _resolveLiveToken();
    tokenFetch.ignore();
    _prefetchedToken = tokenFetch;
    final engineDiagnostics = await _audioPlayer.start(sampleRate: 24000);
    _logConnectionPhase('audio_engine_started', startStopwatch);
    if (engineDiagnostics != null) {
      // iOS voice engine state (voice processing, formats, route). Persisted
      // with the session events so failed rounds are diagnosable without a
      // console attached — see AUDIO.md § iOS.
      _emit(VoiceSystemEvent('Voice engine: $engineDiagnostics'));
    }
    await _connect();
  }

  @override
  Future<void> ensureConnected() async {
    if (!isActive || _connected) return;
    _reconnectTimer?.cancel();
    await _connect();
  }

  /// Runs one connection attempt, deduplicating concurrent callers.
  ///
  /// A failed attempt never propagates: any connect error (network loss,
  /// token mint failure, setup timeout) is recorded as a transient event and
  /// retried on the standard backoff, so no caller can turn a bad connection
  /// into a session teardown. The user always keeps the conversation and the
  /// explicit End button.
  Future<void> _connect() {
    final existing = _connectFuture;
    if (existing != null) return existing;
    final future = _connectOnce().then<void>(
      (_) {},
      onError: (Object error) {
        if (!isActive) return;
        _emit(
          VoiceErrorEvent('Connect attempt failed: $error', isTransient: true),
        );
        _scheduleReconnect();
      },
    );
    _connectFuture = future;
    return future.whenComplete(() {
      if (identical(_connectFuture, future)) _connectFuture = null;
    });
  }

  Future<void> _connectOnce() async {
    if (!isActive) return;
    final connectStopwatch = Stopwatch()..start();
    final prefetched = _prefetchedToken ?? takePrefetchedToken?.call();
    _prefetchedToken = null;
    final effectiveToken = prefetched != null
        ? await prefetched
        : await _resolveLiveToken();
    if (apiKey.isEmpty && effectiveToken.isEmpty) {
      throw StateError(
        'Missing Gemini credentials. Configure an authenticated Convex '
        'account, GEMINI_LIVE_TOKEN, or GEMINI_API_KEY.',
      );
    }
    _logConnectionPhase('token_resolved', connectStopwatch, {
      'prefetched': prefetched != null,
    });

    final generation = ++_connectionGeneration;
    final uri = _connectionUri(effectiveToken);
    final setupComplete = Completer<void>();
    _setupComplete = setupComplete;
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    // Status writes queue behind the session's serialized write chain, which
    // can be deep in buffered audio during a reconnect — keep them off the
    // handshake's critical path. `_serial()` still preserves call order.
    unawaited(sessionRepository.markStatus(_sessionId!, 'connecting'));

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
        // No resume handle is presented: after an abrupt disconnect a stale
        // handle makes the server silently open a BLANK session (see
        // buildConversationSeed). Context is restored by the transcript seed
        // sent right after setup instead. Resumption updates still arrive
        // (the minted token enables them) and their timestamps drive the
        // local session-freshness gate.
        'sessionResumption': <String, dynamic>{},
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
    // Every connect is a fresh server session; restore the conversation from
    // the durable log before anything else is sent, so queued messages and
    // live audio land after the model regained its context.
    final seed = await _buildContextSeed();
    if (generation != _connectionGeneration || !isActive) return;
    _connected = true;
    _reconnectAttempt = 0;
    _logConnectionPhase('setup_complete', connectStopwatch);
    unawaited(sessionRepository.markStatus(_sessionId!, 'active'));
    if (seed != null) {
      _sendNow({
        'clientContent': {
          'turns': [
            {
              'role': 'user',
              'parts': [
                {'text': seed},
              ],
            },
          ],
          'turnComplete': false,
        },
      });
      _logConnectionPhase('context_seeded', connectStopwatch, {
        'chars': seed.length,
      });
    }
    _emit(VoiceConnectedEvent());
    _flushPendingMessages();
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
  Future<String> _resolveLiveToken() async {
    if (liveToken.isNotEmpty) return liveToken;
    _emit(VoiceSystemEvent('Requesting live token from Convex'));
    final token = await _fetchLiveToken(
      useAuthenticatedTokenAction: useAuthenticatedTokenAction,
      convexClient: convexClient,
      sessionToken: sessionToken,
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
    _mutedByDetach = false;
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
    _prefetchedToken = null;
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
    // Best-effort replication: offline this can sit on the Convex client's
    // 30 s operation timeout, and ending the conversation must never wait on
    // it. Unsynced rows stay in the durable outbox and retry later.
    unawaited(remoteSync?.flush());
    onEnded();
    return VoiceExpenseCommandResult(message: summary);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    _prefetchedToken = null;
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
    _goAwayTimer?.cancel();
    // Reconnect shortly before the announced kill; the transcript seed
    // restores context on the new connection.
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
      _interactionCostTracker.markToolCall();
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
    final sample = _interactionCostTracker.nextSample(
      sessionId: sessionId,
      totalCostUsd: totalCostUsd,
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
