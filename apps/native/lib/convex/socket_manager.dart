import 'dart:async';
import 'dart:io' as io;
import 'dart:math';

import 'package:clock/clock.dart';

import 'errors.dart';
import 'protocol.dart';

/// Minimal WebSocket surface so the whole protocol stack runs under plain
/// `flutter test` with a fake socket (docs/dart-convex-client.md §5, §10).
abstract interface class ConvexWebSocket {
  /// Incoming text frames. Done = socket closed.
  Stream<String> get messages;
  void send(String data);
  Future<void> close([int? code, String? reason]);
  int? get closeCode;
  String? get closeReason;
}

typedef ConvexSocketFactory =
    Future<ConvexWebSocket> Function(Uri uri, Map<String, String> headers);

/// Production factory over `dart:io`.
Future<ConvexWebSocket> ioConvexSocketFactory(
  Uri uri,
  Map<String, String> headers,
) async {
  final socket = await io.WebSocket.connect(uri.toString(), headers: headers);
  return _IoConvexWebSocket(socket);
}

class _IoConvexWebSocket implements ConvexWebSocket {
  _IoConvexWebSocket(this._socket);
  final io.WebSocket _socket;

  @override
  Stream<String> get messages => _socket.map((frame) => frame as String);

  @override
  void send(String data) => _socket.add(data);

  @override
  Future<void> close([int? code, String? reason]) =>
      _socket.close(code, reason);

  @override
  int? get closeCode => _socket.closeCode;

  @override
  String? get closeReason => _socket.closeReason;
}

/// Tunables for the socket lifecycle; every wait is configurable (§2, §7).
class SocketManagerConfig {
  const SocketManagerConfig({
    this.handshakeTimeout = const Duration(seconds: 10),
    this.serverInactivityThreshold = const Duration(seconds: 45),
    this.initialBackoff = const Duration(milliseconds: 250),
    this.serverErrorBackoff = const Duration(seconds: 1),
    this.overloadBackoff = const Duration(seconds: 3),
    this.maxBackoff = const Duration(seconds: 16),
    this.maxReconnectAttempts,
    this.restartTimeout = const Duration(seconds: 20),
  });

  /// Covers DNS + TLS + WS upgrade — the fix for "stuck in connecting
  /// forever" (convex_flutter #14/#18).
  final Duration handshakeTimeout;

  /// The server pings ~every 15 s; no frame for this long means the socket is
  /// a zombie and gets closed (`InactiveServer`).
  final Duration serverInactivityThreshold;

  /// Backoff floor for client-initiated closes and connect failures.
  final Duration initialBackoff;

  /// Backoff floor after a server `InternalServerError` close (§A.8).
  final Duration serverErrorBackoff;

  /// Backoff floor after server-overload close reasons (§A.8).
  final Duration overloadBackoff;
  final Duration maxBackoff;

  /// Null = retry forever (the default).
  final int? maxReconnectAttempts;

  /// Bounds the restart sequence (§5.2) — in practice the auth token fetch,
  /// its only await. A hung fetch must not park the socket in `connecting`
  /// forever while server pings keep the watchdog happy.
  final Duration restartTimeout;
}

class ConnectionSnapshot {
  const ConnectionSnapshot({
    required this.status,
    required this.retries,
    required this.lastCloseReason,
  });

  final ConnectionStatus status;
  final int retries;
  final String? lastCloseReason;

  @override
  String toString() =>
      'ConnectionSnapshot(${status.name}, retries: $retries, '
      'lastClose: $lastCloseReason)';
}

const _overloadCloseReasonPrefixes = [
  'SubscriptionsWorkerFullError',
  'TooManyConcurrentRequests',
  'CommitterFullError',
  'ExecuteFullError',
  'SystemTimeoutError',
  'ExpiredInQueue',
  'TooManyWritesInTimePeriod',
];

const _clientCloseReasons = [
  'InitialConnect',
  'InactiveServer',
  'AuthError',
  'ProtocolError',
  'ClientReconnect',
  'HandshakeTimeout',
  'ConnectError',
  'RestartError',
];

/// WebSocket lifecycle: the §5.1 state machine, exponential backoff with
/// per-close-reason floors, the inactivity watchdog, and the proactive
/// reconnect triggers. Terminal only via [dispose] (or the client reacting to
/// a FatalError by calling it).
class SocketManager {
  SocketManager({
    required this.uri,
    required this.headers,
    required this.factory,
    required this.config,
    required this.onOpen,
    required this.onFrame,
    required this.onStateChange,
    required this.emitEvent,
    Random? random,
  }) : _random = random ?? Random();

  final Uri uri;
  final Map<String, String> headers;
  final ConvexSocketFactory factory;
  final SocketManagerConfig config;

  /// The restart sequence (§5.2). Runs on every socket open; sends Connect /
  /// Authenticate / ModifyQuerySet / mutation resends via [sendDirect] and
  /// [sendOrBuffer]. When it throws, the socket is torn down and retried.
  final Future<void> Function() onOpen;
  final void Function(String frame) onFrame;
  final void Function(ConnectionSnapshot snapshot) onStateChange;
  final void Function(String type, Map<String, Object?> data) emitEvent;
  final Random _random;

  ConvexWebSocket? _socket;
  StreamSubscription<String>? _socketSub;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  int _retries = 0;
  String? _lastCloseReason = 'InitialConnect';
  int _attempt = 0;
  bool _disposed = false;
  bool _started = false;
  bool _restarting = false;
  bool _paused = false;
  bool _reconnectImmediately = false;
  final List<ClientMessage> _buffer = [];
  Timer? _backoffTimer;
  DateTime? _backoffDeadline;
  Timer? _handshakeTimer;
  Timer? _watchdogTimer;
  DateTime? _lastFrameAt;

  ConnectionStatus get status => _status;
  int get retries => _retries;
  String? get lastCloseReason => _lastCloseReason;
  bool get isDisposed => _disposed;

  /// Whether a message handed over now will be delivered on this socket
  /// (directly or via the restart buffer).
  bool get canDeliver => _socket != null;

  ConnectionSnapshot get snapshot => ConnectionSnapshot(
    status: _status,
    retries: _retries,
    lastCloseReason: _lastCloseReason,
  );

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _connect();
  }

  void _setStatus(ConnectionStatus next) {
    if (_status == next) return;
    _status = next;
    onStateChange(snapshot);
  }

  Future<void> _connect() async {
    if (_disposed ||
        _socket != null ||
        _status == ConnectionStatus.connecting) {
      return;
    }
    _backoffTimer?.cancel();
    _backoffTimer = null;
    _backoffDeadline = null;
    final attempt = ++_attempt;
    _setStatus(ConnectionStatus.connecting);
    emitEvent('socket.connecting', {'attempt': attempt, 'retries': _retries});
    _armWatchdog();
    final handshakeCompleter = Completer<ConvexWebSocket>();
    _handshakeTimer = Timer(config.handshakeTimeout, () {
      if (!handshakeCompleter.isCompleted) {
        handshakeCompleter.completeError(
          TimeoutException('handshake', config.handshakeTimeout),
        );
      }
    });
    unawaited(
      factory(uri, headers).then(
        (socket) {
          if (handshakeCompleter.isCompleted) {
            // Timed out or superseded: this socket has no owner.
            unawaited(socket.close(1000, 'HandshakeTimeout'));
          } else {
            handshakeCompleter.complete(socket);
          }
        },
        onError: (Object error) {
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.completeError(error);
          }
        },
      ),
    );
    final ConvexWebSocket socket;
    try {
      socket = await handshakeCompleter.future;
    } catch (error) {
      _handshakeTimer?.cancel();
      if (_disposed || attempt != _attempt) return;
      final reason = error is TimeoutException
          ? 'HandshakeTimeout'
          : 'ConnectError: $error';
      emitEvent('socket.connectFailed', {'reason': reason});
      _setStatus(ConnectionStatus.disconnected);
      _scheduleReconnect(reason);
      return;
    }
    _handshakeTimer?.cancel();
    if (_disposed || attempt != _attempt) {
      unawaited(socket.close(1000, 'Superseded'));
      return;
    }
    _socket = socket;
    _armWatchdog();
    _socketSub = socket.messages.listen(
      (frame) {
        _lastFrameAt = clock.now();
        _armWatchdog();
        onFrame(frame);
      },
      onDone: () => _onSocketClosed(attempt),
      onError: (Object error) {
        emitEvent('socket.streamError', {'error': '$error'});
        _onSocketClosed(attempt);
      },
    );
    emitEvent('socket.open', {'attempt': attempt});
    _restarting = true;
    try {
      await onOpen().timeout(config.restartTimeout);
    } catch (error) {
      emitEvent('socket.restartFailed', {'error': '$error'});
      if (attempt == _attempt) {
        _closeAndReconnect('RestartError: $error');
      }
      return;
    } finally {
      _restarting = false;
    }
    if (_disposed || attempt != _attempt || _socket != socket) return;
    _setStatus(ConnectionStatus.ready);
    emitEvent('socket.ready', {'attempt': attempt});
    _flushBuffer();
  }

  void _onSocketClosed(int attempt) {
    if (attempt != _attempt || _socket == null) return;
    final reason = _describeClose(_socket!);
    emitEvent('socket.closed', {'reason': reason});
    _teardownSocket();
    if (_disposed) return;
    _setStatus(ConnectionStatus.disconnected);
    _scheduleReconnect(reason);
  }

  String _describeClose(ConvexWebSocket socket) {
    final reason = socket.closeReason;
    if (reason != null && reason.isNotEmpty) return reason;
    final code = socket.closeCode;
    return code == null ? 'closed' : 'closed-$code';
  }

  void _teardownSocket() {
    _socketSub?.cancel();
    _socketSub = null;
    _socket = null;
    _restarting = false;
    _paused = false;
    // No message composed before a reconnect may survive it (§5.2 rule 5).
    _buffer.clear();
    _watchdogTimer?.cancel();
  }

  /// Closes the current socket (if any) and reconnects with backoff floored
  /// at the client-initiated rate. Used by the watchdog, AuthError handling,
  /// and protocol failures.
  void _closeAndReconnect(String reason) {
    final socket = _socket;
    if (socket != null) {
      _attempt++; // orphan the old socket's callbacks
      _teardownSocket();
      unawaited(socket.close(1000, _shortReason(reason)));
    }
    if (_disposed) return;
    _setStatus(ConnectionStatus.disconnected);
    _scheduleReconnect(reason);
  }

  /// WebSocket close reasons are capped at 123 bytes.
  String _shortReason(String reason) =>
      reason.length <= 100 ? reason : reason.substring(0, 100);

  void closeAndReconnect(String reason) {
    emitEvent('socket.forceClose', {'reason': reason});
    _closeAndReconnect(reason);
  }

  void _scheduleReconnect(String reason) {
    _lastCloseReason = reason;
    onStateChange(snapshot);
    if (_disposed) return;
    if (_reconnectImmediately) {
      _reconnectImmediately = false;
      _connect();
      return;
    }
    final max = config.maxReconnectAttempts;
    if (max != null && _retries >= max) {
      emitEvent('socket.reconnectExhausted', {'retries': _retries});
      _lastCloseReason = 'ReconnectAttemptsExhausted';
      onStateChange(snapshot);
      return;
    }
    final delay = _backoffDelay(reason, _retries);
    _retries++;
    emitEvent('socket.backoff', {
      'delayMs': delay.inMilliseconds,
      'retries': _retries,
      'reason': reason,
    });
    _backoffDeadline = clock.now().add(delay);
    _backoffTimer = Timer(delay, _connect);
  }

  Duration _backoffDelay(String reason, int retries) {
    final floorMs = _initialBackoffFor(reason).inMilliseconds;
    final exponentialMs = floorMs * pow(2, retries);
    final cappedMs = min(
      exponentialMs.toDouble(),
      config.maxBackoff.inMilliseconds.toDouble(),
    );
    final jitteredMs = cappedMs * (0.5 + _random.nextDouble());
    return Duration(milliseconds: jitteredMs.round());
  }

  Duration _initialBackoffFor(String reason) {
    if (_overloadCloseReasonPrefixes.any(reason.startsWith)) {
      return config.overloadBackoff;
    }
    if (reason.startsWith('InternalServerError')) {
      return config.serverErrorBackoff;
    }
    if (_clientCloseReasons.any(reason.startsWith)) {
      return config.initialBackoff;
    }
    return config.serverErrorBackoff;
  }

  /// Proactive trigger (§5.1): connectivity regained, app resumed, or an
  /// explicit reconnect request while disconnected — skip any pending backoff
  /// and connect now. Also resumes after `maxReconnectAttempts` gave up.
  void wakeUp() {
    if (_disposed || !_started) return;
    if (_socket != null) return;
    final max = config.maxReconnectAttempts;
    if (max != null && _retries >= max) _retries = 0;
    emitEvent('socket.wakeUp', {});
    _connect();
  }

  /// A queued call arrived while a long backoff is pending: cap the remaining
  /// wait at the initial backoff (§5.1 trigger 4).
  void nudge() {
    if (_disposed) return;
    final deadline = _backoffDeadline;
    if (deadline == null) return;
    final remaining = deadline.difference(clock.now());
    if (remaining <= config.initialBackoff) return;
    emitEvent('socket.nudge', {'remainingMs': remaining.inMilliseconds});
    _backoffTimer?.cancel();
    _backoffDeadline = clock.now().add(config.initialBackoff);
    _backoffTimer = Timer(config.initialBackoff, _connect);
  }

  /// A real close-and-reopen, unlike the Rust client's `reconnect()`.
  void reconnectNow() {
    if (_disposed || !_started) return;
    if (_socket != null) {
      _reconnectImmediately = true;
      _closeAndReconnect('ClientReconnect');
    } else {
      wakeUp();
    }
  }

  /// Backoff resets only after a full resync (§3): the client calls this once
  /// all re-added queries answered, auth is confirmed, and pre-restart
  /// requests are done.
  void markResynced() {
    if (_retries == 0) return;
    _retries = 0;
    emitEvent('socket.resynced', {});
    onStateChange(snapshot);
  }

  /// On app resume: if the last frame is older than the inactivity threshold,
  /// the socket is a zombie — replace it now instead of waiting for the
  /// watchdog (§5.1).
  void checkInactivityNow() {
    if (_socket == null) return;
    final last = _lastFrameAt;
    if (last == null) return;
    if (clock.now().difference(last) >= config.serverInactivityThreshold) {
      _closeAndReconnect('InactiveServer');
    }
  }

  void _armWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(config.serverInactivityThreshold, () {
      emitEvent('socket.inactive', {
        'thresholdMs': config.serverInactivityThreshold.inMilliseconds,
      });
      _closeAndReconnect('InactiveServer');
    });
  }

  /// Sends now when the socket is ready and unpaused; buffers during the
  /// restart sequence or an auth pause. Returns false when there is no
  /// socket — the caller's state (queued request / subscription registry) is
  /// the source of truth and the next restart re-sends it.
  bool sendOrBuffer(ClientMessage message) {
    if (_socket == null) return false;
    if (_restarting || _paused || _status != ConnectionStatus.ready) {
      _buffer.add(message);
      return true;
    }
    _sendNow(message);
    return true;
  }

  /// Restart-sequence sends (Connect, Authenticate) that must bypass the
  /// buffer to keep the §5.2 ordering.
  void sendDirect(ClientMessage message) {
    final socket = _socket;
    if (socket == null) {
      throw StateError('sendDirect with no socket');
    }
    socket.send(message.encode());
  }

  void _sendNow(ClientMessage message) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.send(message.encode());
    } catch (error) {
      emitEvent('socket.sendFailed', {'error': '$error'});
    }
  }

  /// Pause/resume outgoing non-restart traffic (§6.1): queued messages keep
  /// FIFO order and flush on resume.
  void pause() {
    _paused = true;
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    if (_status == ConnectionStatus.ready) _flushBuffer();
  }

  void _flushBuffer() {
    if (_socket == null || _paused || _restarting) return;
    while (_buffer.isNotEmpty && _socket != null) {
      _sendNow(_buffer.removeAt(0));
    }
  }

  Future<void> dispose([String reason = 'ClientDisposed']) async {
    if (_disposed) return;
    _disposed = true;
    _backoffTimer?.cancel();
    _handshakeTimer?.cancel();
    _watchdogTimer?.cancel();
    final socket = _socket;
    _attempt++;
    _teardownSocket();
    _lastCloseReason = reason;
    _setStatus(ConnectionStatus.disconnected);
    if (socket != null) {
      // Not awaited: a wedged close handshake must never stall disposal.
      unawaited(socket.close(1000, reason));
    }
  }
}
