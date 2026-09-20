import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import 'live_protocol.dart';

enum LiveConnectionState { idle, connecting, ready, reconnecting, closed }

/// Owns exactly one socket. Every asynchronous continuation is fenced by an
/// epoch, including credential fetches and setup. Audio and tool results are
/// never retained across sockets; only the application may queue user text.
class LiveConnection {
  LiveConnection({
    required this.credentials,
    required this.onMessage,
    required this.onState,
    required this.onError,
    required this.beforeReady,
    this.onSend,
    WebSocketChannel Function(Uri)? connectSocket,
    this.setupTimeout = const Duration(seconds: 20),
  }) : _connectSocket = connectSocket ?? WebSocketChannel.connect;

  final Future<Uri> Function() credentials;
  final void Function(Map<String, dynamic>, int) onMessage;
  final void Function(LiveConnectionState) onState;
  final void Function(Object) onError;
  final Future<String?> Function() beforeReady;
  final void Function(Map<String, dynamic>)? onSend;
  final WebSocketChannel Function(Uri) _connectSocket;
  final Duration setupTimeout;
  LiveConnectionState state = LiveConnectionState.idle;
  int epoch = 0;
  int _attempt = 0;
  bool _closed = false;
  WebSocketChannel? _socket;
  StreamSubscription? _subscription;
  Completer<void>? _setup;
  Future<void>? _opening;
  Timer? _retry;
  Timer? _rotation;

  bool get ready => state == LiveConnectionState.ready && !_closed;
  bool isCurrent(int value) => !_closed && epoch == value;

  Future<void> connect() {
    if (_closed || ready) return Future.value();
    final existing = _opening;
    if (existing != null) return existing;
    _retry?.cancel();
    final operation = _open();
    _opening = operation;
    return operation.whenComplete(() {
      if (identical(_opening, operation)) _opening = null;
    });
  }

  Future<void> _open() async {
    final current = ++epoch;
    _setState(LiveConnectionState.connecting);
    try {
      await _release();
      final uri = await credentials();
      if (!isCurrent(current)) return;
      final socket = _connectSocket(uri);
      _socket = socket;
      final setup = Completer<void>();
      _setup = setup;
      // Install an error listener immediately, even before socket.ready.
      setup.future.ignore();
      _subscription = socket.stream.listen(
        (raw) {
          if (!isCurrent(current)) return;
          try {
            final message = LiveProtocol.decode(raw);
            if (message.containsKey('setupComplete') && !setup.isCompleted) {
              setup.complete();
            }
            final error = message['error'];
            if (error != null) {
              throw StateError('Gemini rejected the session: $error');
            }
            onMessage(message, current);
          } catch (error) {
            _failed(error, current);
          }
        },
        onError: (Object error) => _failed(error, current),
        onDone: () {
          _failed(
            StateError(
              'Live socket closed (${socket.closeCode}): ${socket.closeReason ?? ''}',
            ),
            current,
          );
        },
      );
      await socket.ready.timeout(setupTimeout);
      if (!isCurrent(current)) return;
      _write(LiveProtocol.setup());
      await setup.future.timeout(setupTimeout);
      if (!isCurrent(current)) return;
      final seed = await beforeReady();
      if (!isCurrent(current)) return;
      if (seed != null) _write(LiveProtocol.text(seed, complete: false));
      _attempt = 0;
      _setState(LiveConnectionState.ready);
    } catch (error) {
      _failed(error, current);
    }
  }

  bool send(Map<String, dynamic> message, {int? expectedEpoch}) {
    if (!ready || (expectedEpoch != null && expectedEpoch != epoch)) {
      return false;
    }
    try {
      _write(message);
      return true;
    } catch (error) {
      _failed(error, epoch);
      return false;
    }
  }

  void _write(Map<String, dynamic> message) {
    _socket!.sink.add(jsonEncode(message));
    onSend?.call(message);
  }

  void rotateAfter(Duration remaining) {
    _rotation?.cancel();
    _rotation = Timer(
      remaining > const Duration(seconds: 2)
          ? remaining - const Duration(seconds: 2)
          : const Duration(milliseconds: 100),
      reconnect,
    );
  }

  Future<void> reconnect() async {
    if (_closed) return;
    ++epoch;
    _retry?.cancel();
    _rotation?.cancel();
    _opening = null;
    _setState(LiveConnectionState.reconnecting);
    await connect();
  }

  void _failed(Object error, int current) {
    if (!isCurrent(current)) return;
    ++epoch; // Fence late messages and outstanding tools immediately.
    final setup = _setup;
    if (setup != null && !setup.isCompleted) setup.completeError(error);
    _rotation?.cancel();
    _setState(LiveConnectionState.reconnecting);
    onError(error);
    if (_closed) return;
    final seconds = math.min(30, 1 << math.min(_attempt++, 5));
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds), () {
      _opening = null;
      unawaited(connect());
    });
    unawaited(_release());
  }

  void _setState(LiveConnectionState next) {
    state = next;
    onState(next);
  }

  Future<void> _release() async {
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    await subscription?.cancel();
    if (socket != null) {
      try {
        await socket.sink.close().timeout(const Duration(seconds: 2));
      } catch (_) {
        /* A dead network must not block cleanup. */
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++epoch;
    _retry?.cancel();
    _rotation?.cancel();
    final setup = _setup;
    if (setup != null && !setup.isCompleted) {
      setup.completeError(StateError('Live session closed'));
    }
    _setState(LiveConnectionState.closed);
    await _release();
  }
}
