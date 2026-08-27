import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'auth_manager.dart';
import 'errors.dart';
import 'local_query_set.dart';
import 'protocol.dart';
import 'request_manager.dart';
import 'server_state.dart';
import 'socket_manager.dart';
import 'values.dart';

export 'auth_manager.dart' show AuthState, TokenFetcher;
export 'errors.dart';
export 'socket_manager.dart'
    show ConnectionSnapshot, ConvexSocketFactory, ConvexWebSocket;
export 'values.dart' show ConvexValueException;

/// Pure-Dart Convex client (docs/dart-convex-client.md). Speaks the sync
/// protocol over one WebSocket, recovers from anything short of a FatalError,
/// and makes every wait configurable.

class ConvexClientConfig {
  const ConvexClientConfig({
    required this.deploymentUrl,
    required this.clientId,
    this.handshakeTimeout = const Duration(seconds: 10),
    this.serverInactivityThreshold = const Duration(seconds: 45),
    this.initialBackoff = const Duration(milliseconds: 250),
    this.serverErrorBackoff = const Duration(seconds: 1),
    this.overloadBackoff = const Duration(seconds: 3),
    this.maxBackoff = const Duration(seconds: 16),
    this.maxReconnectAttempts,
    this.defaultOperationTimeout = const Duration(seconds: 30),
    this.defaultConnectTimeout,
    this.authRefreshLeeway = const Duration(seconds: 60),
    this.maxFreshAuthFailures = 2,
    this.authRetryInterval = const Duration(seconds: 60),
    this.authFetchTimeout = const Duration(seconds: 15),
    this.restartTimeout = const Duration(seconds: 20),
  });

  /// `https://{deployment}.convex.cloud`.
  final String deploymentUrl;

  /// Sent as the `Convex-Client` upgrade header and on HTTP fallback calls.
  /// Verified against the managed backend (§13.1 spike, 2026-08-26): unknown
  /// identifiers like `dart-0.1.0` and `wallet-bot-flutter/1.0.0+1` are
  /// accepted with no deprecation warnings.
  final String clientId;

  final Duration handshakeTimeout;
  final Duration serverInactivityThreshold;
  final Duration initialBackoff;
  final Duration serverErrorBackoff;
  final Duration overloadBackoff;
  final Duration maxBackoff;

  /// Null = reconnect forever (the default).
  final int? maxReconnectAttempts;

  /// Default bound on "sent but no response". Null = wait forever.
  final Duration? defaultOperationTimeout;

  /// Default bound on "waiting for a ready socket". Null = queue while
  /// offline (the default).
  final Duration? defaultConnectTimeout;

  /// Refresh auth this long before the JWT's `exp`.
  final Duration authRefreshLeeway;

  /// Consecutive fresh-token failures before running unauthenticated (§6.4).
  final int maxFreshAuthFailures;

  /// Retry cadence after auth downgraded to `refreshFailed`.
  final Duration authRetryInterval;

  /// Timebox on every token-fetcher call.
  final Duration authFetchTimeout;

  /// Bounds the restart sequence on a fresh socket (backstop for anything
  /// that would otherwise park it in `connecting` forever).
  final Duration restartTimeout;
}

enum HttpFallback {
  none,

  /// Queries/actions only: when the socket is not `ready`, run the call as a
  /// one-shot HTTP request instead of queueing (§7). Mutations never fall
  /// back — WebSocket mutations are exactly-once via (sessionId, requestId)
  /// dedup and HTTP has no equivalent.
  whenNotReady,
}

/// Per-call waiting policy (§7). `null` means wait forever; [useDefault]
/// (the default) means use the `ConvexClientConfig` value.
class CallOptions {
  const CallOptions({
    this.connectTimeout = useDefault,
    this.operationTimeout = useDefault,
    this.httpFallback = HttpFallback.none,
  });

  /// Sentinel: fall back to the config default. Never used as a real timeout.
  static const Duration useDefault = Duration(microseconds: -1);

  final Duration? connectTimeout;
  final Duration? operationTimeout;
  final HttpFallback httpFallback;
}

/// Structured log/telemetry hook payload (§2 observability goal).
class ConvexClientEvent {
  ConvexClientEvent({required this.at, required this.type, required this.data});

  final DateTime at;
  final String type;
  final Map<String, Object?> data;

  @override
  String toString() => '[$at] $type $data';
}

/// Handle returned by [ConvexClient.subscribe]; [cancel] is idempotent.
class SubscriptionHandle {
  SubscriptionHandle._(this._client, this._query, this.onUpdate, this.onError);

  final ConvexClient _client;
  final LocalQuery _query;
  final void Function(Object? value) onUpdate;
  final void Function(ConvexFunctionError error) onError;
  bool _active = true;

  bool get isActive => _active;

  void cancel() {
    if (!_active) return;
    _active = false;
    _client._unsubscribe(this);
  }
}

class HttpPostResponse {
  const HttpPostResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

typedef HttpPoster =
    Future<HttpPostResponse> Function(
      Uri uri,
      Map<String, String> headers,
      String body,
    );

Future<HttpPostResponse> _defaultHttpPoster(
  Uri uri,
  Map<String, String> headers,
  String body,
) async {
  final response = await http.post(uri, headers: headers, body: body);
  return HttpPostResponse(response.statusCode, response.body);
}

class _ResyncTarget {
  _ResyncTarget({
    required this.querySetVersion,
    required this.requestIds,
    required this.authPending,
  });

  final int querySetVersion;
  final Set<int> requestIds;
  final bool authPending;
}

class ConvexClient {
  ConvexClient(
    this.config, {
    ConvexSocketFactory? socketFactory,
    HttpPoster? httpPoster,
    Random? random,
    String? sessionId,
  }) : _httpPoster = httpPoster ?? _defaultHttpPoster,
       sessionId = sessionId ?? const Uuid().v4() {
    _requests = RequestManager(
      connectionStatus: () => _socket.status,
      decodeValue: jsonToConvex,
    );
    _auth = AuthManager(
      sendMessage: _sendAuthMessage,
      canSendNow: () => _socket.status == ConnectionStatus.ready,
      restartSocket: (reason) => _socket.closeAndReconnect(reason),
      pauseSocket: () => _socket.pause(),
      resumeSocket: () => _socket.resume(),
      onStateChange: _onAuthStateChange,
      emitEvent: _emit,
      refreshLeeway: config.authRefreshLeeway,
      maxFreshFailures: config.maxFreshAuthFailures,
      retryInterval: config.authRetryInterval,
      fetchTimeout: config.authFetchTimeout,
    );
    _socket = SocketManager(
      uri: _wsUri(config.deploymentUrl),
      headers: {'Convex-Client': config.clientId},
      factory: socketFactory ?? ioConvexSocketFactory,
      config: SocketManagerConfig(
        handshakeTimeout: config.handshakeTimeout,
        serverInactivityThreshold: config.serverInactivityThreshold,
        initialBackoff: config.initialBackoff,
        serverErrorBackoff: config.serverErrorBackoff,
        overloadBackoff: config.overloadBackoff,
        maxBackoff: config.maxBackoff,
        maxReconnectAttempts: config.maxReconnectAttempts,
        restartTimeout: config.restartTimeout,
      ),
      onOpen: _onSocketOpen,
      onFrame: _onFrame,
      onStateChange: _onConnectionChange,
      emitEvent: _emit,
      random: random,
    );
    _socket.start();
  }

  final ConvexClientConfig config;

  /// Stable for the client's lifetime and reused across reconnects, so the
  /// server dedupes resent mutations per (sessionId, requestId) — the
  /// exactly-once property the Rust client family lost (§3).
  final String sessionId;

  final HttpPoster _httpPoster;
  late final SocketManager _socket;
  late final RequestManager _requests;
  late final AuthManager _auth;
  final LocalQuerySet _localState = LocalQuerySet();
  RemoteQuerySet _remote = RemoteQuerySet();
  TransitionChunkAssembler _chunks = TransitionChunkAssembler();
  final Map<int, List<SubscriptionHandle>> _subscribers = {};
  final List<void Function(ConvexClientEvent)> _eventListeners = [];
  final StreamController<ConnectionSnapshot> _connectionController =
      StreamController.broadcast();
  final StreamController<AuthState> _authController =
      StreamController.broadcast();
  int _connectionCount = 0;
  int _restartEpoch = 0;
  BigInt? _maxObservedTimestamp;
  _ResyncTarget? _resyncTarget;
  ConvexFatalError? _fatal;
  bool _disposed = false;

  static Uri _wsUri(String deploymentUrl) {
    final base = Uri.parse(deploymentUrl);
    final scheme = switch (base.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      'wss' || 'ws' => base.scheme,
      _ => throw ArgumentError('unsupported deployment URL: $deploymentUrl'),
    };
    return base.replace(scheme: scheme, path: '/api/sync');
  }

  // ---- Observability (§5.3) ----

  Stream<ConnectionSnapshot> get connectionState =>
      _connectionController.stream;
  ConnectionSnapshot get currentConnectionState => _socket.snapshot;

  Stream<AuthState> get authState => _authController.stream;
  AuthState get currentAuthState => _auth.state;

  /// Registers a structured event listener (telemetry/log hook).
  void onEvent(void Function(ConvexClientEvent event) listener) {
    _eventListeners.add(listener);
  }

  void _emit(String type, Map<String, Object?> data) {
    if (_eventListeners.isEmpty) return;
    final event = ConvexClientEvent(at: clock.now(), type: type, data: data);
    for (final listener in List.of(_eventListeners)) {
      try {
        listener(event);
      } catch (_) {
        // A telemetry listener must never break the client.
      }
    }
  }

  void _onConnectionChange(ConnectionSnapshot snapshot) {
    if (!_connectionController.isClosed) _connectionController.add(snapshot);
    if (snapshot.status == ConnectionStatus.ready) {
      // Covers setAuth arriving while a restart was already past its auth
      // step: authenticate now instead of waiting for the next reconnect.
      _auth.ensureAuthenticated();
    }
  }

  void _onAuthStateChange(AuthState state) {
    if (!_authController.isClosed) _authController.add(state);
  }

  // ---- Auth (§6) ----

  /// Installs the token fetcher. The fetcher returning null means "signed
  /// out"; throwing means a transient failure (retried per §6.4).
  void setAuth({required TokenFetcher fetchToken}) {
    _ensureUsable();
    _auth.setAuth(fetchToken);
  }

  void clearAuth() {
    _ensureUsable();
    _auth.clearAuth();
  }

  /// A currently-valid JWT for out-of-band HTTP use (voice token endpoint,
  /// telemetry), without re-minting one per call (§6.5).
  Future<String?> validToken() => _auth.validToken();

  void _sendAuthMessage(ClientMessage message) {
    // Auth messages bypass the pause buffer: an Authenticate must reach the
    // server before any mutation queued behind the pause (§6.1).
    if (_socket.canDeliver) _socket.sendDirect(message);
  }

  // ---- Lifecycle (§5.3) ----

  /// Really closes and reopens the socket, unlike the Rust `reconnect()`.
  Future<void> reconnectNow() async {
    _ensureUsable();
    _socket.reconnectNow();
  }

  /// Connectivity-regained hint: skip any pending backoff (§5.1). Never a
  /// gate — the client also keeps its own timers.
  void onNetworkAvailable() {
    if (_disposed || _fatal != null) return;
    _socket.wakeUp();
  }

  /// Interface-set-changed hint (WiFi → cellular, VPN up or down). No outage
  /// is reported for this, but a socket bound to the old route is already
  /// dead and stays `open`: writes vanish and the 45 s watchdog is the only
  /// thing that would eventually notice. Replace it now.
  void onNetworkChanged() {
    if (_disposed || _fatal != null) return;
    _socket.reconnectNow();
  }

  /// App-resumed hint: mobile OSes kill sockets in the background. Fast-check
  /// the watchdog and reconnect immediately if needed (§5.1).
  void onAppResumed() {
    if (_disposed || _fatal != null) return;
    _socket.checkInactivityNow();
    _socket.wakeUp();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _requests.failAll(ClientDisposedError());
    for (final subs in _subscribers.values) {
      for (final sub in subs) {
        sub._active = false;
      }
    }
    _subscribers.clear();
    _auth.dispose();
    await _socket.dispose();
    await _connectionController.close();
    await _authController.close();
  }

  void _ensureUsable() {
    final fatal = _fatal;
    if (fatal != null) throw fatal;
    if (_disposed) throw ClientDisposedError();
  }

  // ---- Operations (§5.3) ----

  Future<T> query<T>(
    String name,
    Map<String, Object?> args, {
    CallOptions? options,
  }) async {
    _ensureUsable();
    final opts = options ?? const CallOptions();
    final connectTimeout = _resolveTimeout(
      opts.connectTimeout,
      config.defaultConnectTimeout,
    );
    final operationTimeout = _resolveTimeout(
      opts.operationTimeout,
      config.defaultOperationTimeout,
    );
    if (opts.httpFallback == HttpFallback.whenNotReady &&
        _socket.status != ConnectionStatus.ready) {
      return await _httpCall('query', name, args, operationTimeout) as T;
    }
    final completer = Completer<Object?>();
    Timer? timer;
    StreamSubscription<ConnectionSnapshot>? stateSub;
    SubscriptionHandle? handle;
    void settle(void Function() complete) {
      timer?.cancel();
      stateSub?.cancel();
      handle?.cancel();
      if (!completer.isCompleted) complete();
    }

    void startOperationPhase() {
      timer?.cancel();
      timer = null;
      if (operationTimeout != null) {
        timer = Timer(operationTimeout, () {
          settle(
            () => completer.completeError(
              OperationTimeoutError(
                functionName: name,
                phase: TimeoutPhase.operation,
                timeout: operationTimeout,
                connectionStatus: _socket.status,
              ),
            ),
          );
        });
      }
    }

    if (_socket.status == ConnectionStatus.ready) {
      startOperationPhase();
    } else {
      if (connectTimeout != null) {
        timer = Timer(connectTimeout, () {
          settle(
            () => completer.completeError(
              OperationTimeoutError(
                functionName: name,
                phase: TimeoutPhase.connect,
                timeout: connectTimeout,
                connectionStatus: _socket.status,
              ),
            ),
          );
        });
      }
      stateSub = connectionState.listen((snapshot) {
        if (snapshot.status == ConnectionStatus.ready) {
          stateSub?.cancel();
          startOperationPhase();
        }
      });
    }
    handle = subscribe(
      name,
      args,
      onUpdate: (value) => settle(() => completer.complete(value)),
      onError: (error) => settle(() => completer.completeError(error)),
    );
    return await completer.future as T;
  }

  Future<T> mutation<T>(
    String name,
    Map<String, Object?> args, {
    CallOptions? options,
  }) async {
    final opts = options ?? const CallOptions();
    if (opts.httpFallback != HttpFallback.none) {
      throw ArgumentError(
        'mutations never fall back to HTTP: WebSocket mutations are '
        'exactly-once via session dedup, HTTP would risk double-apply (§7)',
      );
    }
    final result = await _request(name, args, isMutation: true, options: opts);
    return jsonToConvex(result) as T;
  }

  Future<T> action<T>(
    String name,
    Map<String, Object?> args, {
    CallOptions? options,
  }) async {
    final opts = options ?? const CallOptions();
    final operationTimeout = _resolveTimeout(
      opts.operationTimeout,
      config.defaultOperationTimeout,
    );
    if (opts.httpFallback == HttpFallback.whenNotReady &&
        _socket.status != ConnectionStatus.ready) {
      _ensureUsable();
      return await _httpCall('action', name, args, operationTimeout) as T;
    }
    final result = await _request(name, args, isMutation: false, options: opts);
    return jsonToConvex(result) as T;
  }

  Future<Object?> _request(
    String name,
    Map<String, Object?> args, {
    required bool isMutation,
    required CallOptions options,
  }) {
    _ensureUsable();
    final udfPath = normalizeUdfPath(name);
    final argsJson = convexArgsToJson(args);
    final requestId = _requests.nextRequestId();
    final ClientMessage message = isMutation
        ? MutationRequestMessage(
            requestId: requestId,
            udfPath: udfPath,
            argsJson: argsJson,
          )
        : ActionRequestMessage(
            requestId: requestId,
            udfPath: udfPath,
            argsJson: argsJson,
          );
    final delivered = _socket.sendOrBuffer(message);
    final kind = isMutation ? 'mutation' : 'action';
    final started = clock.now();
    _emit('$kind.request', {
      'requestId': requestId,
      'udfPath': udfPath,
      // False means there was no socket object at all, which is the whole
      // reconnect-backoff window. A mutation registered then gets no timer
      // unless the caller passed a connectTimeout, so it waits for the socket
      // for as long as that takes; that wait is what makes an offline write
      // survive. True covers both "on the wire" and "buffered on a socket
      // that is not ready yet", and the latter is bounded by
      // operationTimeout, not connectTimeout.
      'delivered': delivered,
      'connection': _socket.status.name,
    });
    final future = _requests.register(
      requestId: requestId,
      message: message,
      udfPath: udfPath,
      isMutation: isMutation,
      sent: delivered,
      connectTimeout: _resolveTimeout(
        options.connectTimeout,
        config.defaultConnectTimeout,
      ),
      operationTimeout: _resolveTimeout(
        options.operationTimeout,
        config.defaultOperationTimeout,
      ),
      // A mutation queued while offline must wait for the socket — that is
      // the exactly-once guarantee. An action or query with an explicit
      // bound must not.
      boundBeforeSend: !isMutation && _isExplicit(options.operationTimeout),
    );
    if (!delivered) {
      // §5.1 trigger 4: a queued call caps a pending long backoff.
      _socket.nudge();
    }
    // Attaching to the future rather than reaching into RequestManager keeps
    // one exit point for every way a call can end: response, timeout,
    // ConnectionLostError on restart, or the client being disposed. The
    // derived future handles its own error, so this adds no unhandled-error
    // path and the caller still sees the original.
    unawaited(
      future.then(
        (_) => _emit('$kind.completed', {
          'requestId': requestId,
          'udfPath': udfPath,
          'elapsedMs': clock.now().difference(started).inMilliseconds,
        }),
        onError: (Object error) => _emit('$kind.failed', {
          'requestId': requestId,
          'udfPath': udfPath,
          'elapsedMs': clock.now().difference(started).inMilliseconds,
          'error': error.toString(),
        }),
      ),
    );
    return future;
  }

  /// Whether the caller passed a real timeout rather than leaving the
  /// [CallOptions.useDefault] sentinel in place.
  static bool _isExplicit(Duration? value) =>
      !identical(value, CallOptions.useDefault) &&
      value != CallOptions.useDefault;

  static Duration? _resolveTimeout(Duration? value, Duration? configDefault) =>
      identical(value, CallOptions.useDefault) ||
          value == CallOptions.useDefault
      ? configDefault
      : value;

  SubscriptionHandle subscribe(
    String name,
    Map<String, Object?> args, {
    required void Function(Object? value) onUpdate,
    required void Function(ConvexFunctionError error) onError,
  }) {
    _ensureUsable();
    final udfPath = normalizeUdfPath(name);
    final argsJson = convexArgsToJson(args);
    final (query, message) = _localState.subscribe(udfPath, argsJson);
    final handle = SubscriptionHandle._(this, query, onUpdate, onError);
    _subscribers.putIfAbsent(query.queryId, () => []).add(handle);
    if (message != null) {
      _socket.sendOrBuffer(message);
      _socket.nudge();
    } else {
      final known = _remote.results[query.queryId];
      if (known != null) {
        scheduleMicrotask(() => _deliver(handle, query, known));
      }
    }
    _emit('query.subscribe', {
      'queryId': query.queryId,
      'udfPath': udfPath,
      'new': message != null,
    });
    return handle;
  }

  void _unsubscribe(SubscriptionHandle handle) {
    final queryId = handle._query.queryId;
    final handles = _subscribers[queryId];
    handles?.remove(handle);
    if (handles != null && handles.isEmpty) _subscribers.remove(queryId);
    final message = _localState.unsubscribe(handle._query);
    if (message != null) {
      _socket.sendOrBuffer(message);
      _emit('query.unsubscribe', {'queryId': queryId});
    }
  }

  // ---- Restart sequence (§5.2) ----

  Future<void> _onSocketOpen() async {
    final epoch = ++_restartEpoch;
    // 5) Discard the previous socket's server state before any frame arrives.
    _remote = RemoteQuerySet();
    _chunks = TransitionChunkAssembler();
    _resyncTarget = null;

    // Compose the query-set snapshot and mutation resends synchronously so
    // nothing composed against pre-restart versions can interleave (the
    // convex-rs #14 lesson): the only await below is the token fetch, and
    // anything the app does meanwhile lands in the ordered buffer.
    final querySetRestart = _localState.restart();
    final resend = _requests.restart();

    // 1) Connect — same sessionId, incremented connectionCount.
    _connectionCount++;
    _socket.sendDirect(
      ConnectMessage(
        sessionId: sessionId,
        connectionCount: _connectionCount,
        lastCloseReason: _socket.lastCloseReason ?? 'InitialConnect',
        clientTs: clock.now().millisecondsSinceEpoch,
        maxObservedTimestamp: _maxObservedTimestamp,
      ),
    );

    // 2) Authenticate with a fresh token (§6.3).
    final authenticate = await _auth.restartAuthenticate();
    // The fetch was this sequence's only await: if the restart timed out or a
    // newer socket restarted meanwhile, this continuation must not write onto
    // the new socket.
    if (epoch != _restartEpoch || !_socket.canDeliver) return;
    if (authenticate != null) _socket.sendDirect(authenticate);

    // 3) One ModifyQuerySet 0→1 re-adding every live subscription.
    if (querySetRestart != null) _socket.sendDirect(querySetRestart);

    // 4) Resend in-flight mutations; actions already failed in restart().
    for (final message in resend) {
      _socket.sendDirect(message);
    }

    _resyncTarget = _ResyncTarget(
      querySetVersion: _localState.version,
      requestIds: _requests.inflightRequestIds,
      authPending: _auth.awaitingConfirmation,
    );
    _emit('socket.restarted', {
      'connectionCount': _connectionCount,
      'queries': querySetRestart?.modifications.length ?? 0,
      'resentRequests': resend.length,
      'authenticated': authenticate != null,
    });
    _maybeMarkResynced();
  }

  // ---- Server messages ----

  void _onFrame(String frame) {
    ServerMessage? message;
    try {
      message = _chunks.add(parseServerMessage(frame));
      if (message == null) return;
      _dispatch(message);
    } on ConvexProtocolException catch (error) {
      _emit('protocol.error', {'error': error.message});
      _socket.closeAndReconnect('ProtocolError: ${error.message}');
    }
  }

  void _dispatch(ServerMessage message) {
    switch (message) {
      case TransitionMessage():
        _handleTransition(message);
      case MutationResponseMessage():
        _requests.onMutationResponse(message);
        final ts = message.ts;
        if (ts != null) _observeTimestamp(ts);
        _maybeMarkResynced();
      case ActionResponseMessage():
        _requests.onActionResponse(message);
        _maybeMarkResynced();
      case AuthErrorMessage():
        _auth.onAuthError(message);
      case FatalErrorMessage():
        _handleFatal(message.error);
      case PingMessage():
        break; // watchdog already reset by the frame itself
      case TransitionChunkMessage():
        break; // unreachable: the assembler consumed it
    }
  }

  void _handleTransition(TransitionMessage transition) {
    _auth.onTransition(transition.startVersion, transition.endVersion);
    final changed = _remote.ingest(transition);
    for (final modification in transition.modifications) {
      switch (modification) {
        case QueryUpdatedModification(
          :final queryId,
          :final hasJournal,
          :final journal,
        ):
          if (hasJournal) _localState.saveJournal(queryId, journal);
        case QueryFailedModification(
          :final queryId,
          :final hasJournal,
          :final journal,
        ):
          if (hasJournal) _localState.saveJournal(queryId, journal);
        case QueryRemovedModification():
          break;
      }
    }
    _observeTimestamp(transition.endVersion.ts);
    _requests.removeCompleted(transition.endVersion.ts);
    for (final queryId in changed) {
      final result = _remote.results[queryId];
      final query = _localState.byId(queryId);
      if (result == null || query == null) continue;
      for (final handle in List.of(_subscribers[queryId] ?? const [])) {
        _deliver(handle, query, result);
      }
    }
    _maybeMarkResynced();
  }

  void _deliver(
    SubscriptionHandle handle,
    LocalQuery query,
    QueryResult result,
  ) {
    if (!handle.isActive) return;
    if (result.success) {
      final Object? value;
      try {
        value = jsonToConvex(result.value);
      } on ConvexValueException catch (error) {
        handle.onError(
          ConvexFunctionError(
            functionName: query.udfPath,
            errorMessage: 'undecodable query result: ${error.message}',
          ),
        );
        return;
      }
      handle.onUpdate(value);
    } else {
      handle.onError(
        ConvexFunctionError(
          functionName: query.udfPath,
          errorMessage: result.errorMessage ?? 'query failed',
          errorData: result.errorData == null
              ? null
              : jsonToConvex(result.errorData),
        ),
      );
    }
  }

  void _observeTimestamp(BigInt ts) {
    final max = _maxObservedTimestamp;
    if (max == null || ts > max) _maxObservedTimestamp = ts;
  }

  void _maybeMarkResynced() {
    final target = _resyncTarget;
    if (target == null) return;
    if (_remote.version.querySet < target.querySetVersion) return;
    if (_requests.anyInflightOf(target.requestIds)) return;
    if (target.authPending && _auth.awaitingConfirmation) return;
    _resyncTarget = null;
    _socket.markResynced();
  }

  void _handleFatal(String error) {
    _emit('fatal', {'error': error});
    final fatal = ConvexFatalError(error);
    _fatal = fatal;
    _requests.failAll(fatal);
    _auth.dispose();
    unawaited(_socket.dispose('FatalError'));
    for (final entry in _subscribers.entries) {
      final query = _localState.byId(entry.key);
      for (final handle in List.of(entry.value)) {
        if (!handle.isActive) continue;
        handle.onError(
          ConvexFunctionError(
            functionName: query?.udfPath ?? 'unknown',
            errorMessage: 'fatal protocol error: $error',
          ),
        );
      }
    }
  }

  // ---- HTTP fallback (§7, §A.9) ----

  Future<Object?> _httpCall(
    String kind,
    String name,
    Map<String, Object?> args,
    Duration? operationTimeout,
  ) async {
    final udfPath = normalizeUdfPath(name);
    final argsJson = convexArgsToJson(args);
    final uri = Uri.parse(config.deploymentUrl).replace(path: '/api/$kind');
    _emit('http.fallback', {'kind': kind, 'udfPath': udfPath});
    final started = clock.now();
    // The token lookup is part of the call, not a free preamble: it can miss
    // the cache and go out to the auth fetcher, which has its own 15 s bound.
    // Leaving it outside meant a caller's 6 s deadline could take 15 s plus
    // the post before it ever fired.
    Future<HttpPostResponse> post = _auth.validToken().then(
      (token) => _httpPoster(
        uri,
        {
          'Content-Type': 'application/json',
          'Convex-Client': config.clientId,
          if (token != null) 'Authorization': 'Bearer $token',
        },
        jsonEncode({
          'path': udfPath,
          'format': 'convex_encoded_json',
          'args': [argsJson],
        }),
      ),
    );
    if (operationTimeout != null) {
      post = post.timeout(operationTimeout);
    }
    final HttpPostResponse response;
    try {
      response = await post;
      _emit('http.completed', {
        'kind': kind,
        'udfPath': udfPath,
        'elapsedMs': clock.now().difference(started).inMilliseconds,
        'statusCode': response.statusCode,
      });
    } on TimeoutException {
      _emit('http.timeout', {
        'kind': kind,
        'udfPath': udfPath,
        'elapsedMs': clock.now().difference(started).inMilliseconds,
      });
      throw OperationTimeoutError(
        functionName: udfPath,
        phase: TimeoutPhase.operation,
        timeout: operationTimeout!,
        connectionStatus: _socket.status,
      );
    } catch (error) {
      _emit('http.failed', {
        'kind': kind,
        'udfPath': udfPath,
        'elapsedMs': clock.now().difference(started).inMilliseconds,
        'error': error.toString(),
      });
      throw ConnectionLostError('http $kind failed: $error');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw ConnectionLostError(
        'http $kind returned ${response.statusCode} with a non-JSON body',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw ConnectionLostError('http $kind returned an unexpected body shape');
    }
    if (decoded['status'] == 'success') {
      return jsonToConvex(decoded['value']);
    }
    throw ConvexFunctionError(
      functionName: udfPath,
      errorMessage:
          decoded['errorMessage'] as String? ??
          'http $kind failed with status ${response.statusCode}',
      errorData: decoded['errorData'] == null
          ? null
          : jsonToConvex(decoded['errorData']),
    );
  }
}
