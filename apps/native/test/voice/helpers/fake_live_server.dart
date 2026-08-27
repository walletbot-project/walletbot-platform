import 'dart:async';
import 'dart:convert';

import 'package:app/voice/live_socket.dart';

/// A scriptable stand-in for the Gemini Live endpoint, mirroring
/// `FakeConvexServer` on the Convex side: every connection is captured, can be
/// dropped at any point, and every client frame is recorded for assertions.
class FakeLiveServer {
  FakeLiveServer({this.autoSetupComplete = true, this.refuseConnects = 0});

  /// Whether a connection answers `setup` with `setupComplete` on its own.
  /// Off lets a test park a connect in the handshake.
  bool autoSetupComplete;

  /// Fails this many connects before the next one succeeds — the black-hole
  /// network case.
  int refuseConnects;

  final List<FakeLiveConnection> connections = [];
  final List<Uri> connectUris = [];

  FakeLiveConnection get latest => connections.last;
  int get connectCount => connections.length;

  LiveSocket connect(Uri uri) {
    connectUris.add(uri);
    final connection = FakeLiveConnection(this);
    connections.add(connection);
    if (refuseConnects > 0) {
      refuseConnects -= 1;
      scheduleMicrotask(connection.failConnect);
    }
    return connection;
  }
}

class FakeLiveConnection implements LiveSocket {
  FakeLiveConnection(this._server);

  final FakeLiveServer _server;
  final StreamController<dynamic> _incoming = StreamController<dynamic>();

  /// Every decoded frame the client sent, in order.
  final List<Map<String, Object?>> received = [];

  bool closed = false;
  bool closedByClient = false;
  int? _closeCode;
  String? _closeReason;

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void send(String data) {
    if (closed) throw StateError('send on a closed live socket');
    final frame = (jsonDecode(data) as Map).cast<String, Object?>();
    received.add(frame);
    if (frame.containsKey('setup') && _server.autoSetupComplete) {
      sendSetupComplete();
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (closed) return;
    closed = true;
    closedByClient = true;
    _closeCode = code;
    _closeReason = reason;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  // ---- Server-side script ----

  void emit(Map<String, Object?> message) {
    if (closed || _incoming.isClosed) return;
    _incoming.add(jsonEncode(message));
  }

  void sendSetupComplete() =>
      emit(const {'setupComplete': <String, Object?>{}});

  /// A `sessionResumptionUpdate`. Its only job on the client is to timestamp
  /// the local session-freshness gate; no handle is ever presented back.
  void sendResumptionUpdate({String handle = 'handle-1'}) => emit({
    'sessionResumptionUpdate': {'newHandle': handle, 'resumable': true},
  });

  void sendAgentTranscript(String text) => emit({
    'serverContent': {
      'outputTranscription': {'text': text},
    },
  });

  void sendUserTranscript(String text) => emit({
    'serverContent': {
      'inputTranscription': {'text': text},
    },
  });

  void sendTurnComplete() => emit(const {
    'serverContent': {'turnComplete': true},
  });

  void sendGoAway(String timeLeft) => emit({
    'goAway': {'timeLeft': timeLeft},
  });

  /// The server (or the network) drops the socket. This is what a real
  /// half-open connection looks like once the keepalive finally notices.
  void dropFromServer({int code = 1006, String reason = 'abnormal'}) {
    if (closed) return;
    closed = true;
    _closeCode = code;
    _closeReason = reason;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  void failConnect() {
    if (closed) return;
    if (!_incoming.isClosed) {
      _incoming.addError(StateError('connection refused'));
      unawaited(_incoming.close());
    }
    closed = true;
  }

  /// Frames of one kind, e.g. `clientContent` or `realtimeInput`.
  List<Map<String, Object?>> framesOfKind(String key) =>
      received.where((frame) => frame.containsKey(key)).toList(growable: false);

  /// Text carried by `clientContent` turns, in order. The context seed is the
  /// first one after a reconnect.
  List<String> get clientTexts => [
    for (final frame in framesOfKind('clientContent'))
      ...(((frame['clientContent'] as Map)['turns'] as List)
          .expand((turn) => ((turn as Map)['parts'] as List))
          .map((part) => (part as Map)['text'])
          .whereType<String>()),
  ];
}
