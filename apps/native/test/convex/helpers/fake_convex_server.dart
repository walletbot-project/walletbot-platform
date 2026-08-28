import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/convex/protocol.dart';

/// An in-memory server speaking the Convex sync protocol over a fake socket,
/// scriptable per test (docs/dart-convex-client.md §10): drop the socket at
/// any point, delay or hang the handshake, refuse N connects, send AuthError
/// variants, duplicate MutationResponses, split transitions into chunks.

/// Deterministic jitter: `0.5 + 0.5 = 1.0` → backoff delays are exact.
class FixedRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.5;

  @override
  int nextInt(int max) => 0;
}

class FakeServerSocket implements ConvexWebSocket {
  FakeServerSocket(this.connection);

  final FakeConnection connection;
  final StreamController<String> incoming = StreamController<String>();
  int? _closeCode;
  String? _closeReason;

  @override
  Stream<String> get messages => incoming.stream;

  @override
  void send(String data) {
    if (connection.closed) {
      throw StateError('send on closed socket');
    }
    connection.received.add((jsonDecode(data) as Map).cast<String, Object?>());
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (connection.closed) return;
    _closeCode = code;
    _closeReason = reason;
    connection.closed = true;
    connection.closedByClient = true;
    connection.clientCloseReason = reason;
    // Not awaited: close()'s future never completes once the subscription
    // has been cancelled, and the client cancels before closing.
    if (!incoming.isClosed) incoming.close();
  }

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;
}

class FakeConnection {
  FakeConnection() {
    socket = FakeServerSocket(this);
  }

  late final FakeServerSocket socket;

  /// Every client→server message, JSON-decoded, in arrival order.
  final List<Map<String, Object?>> received = [];
  bool closed = false;
  bool closedByClient = false;
  String? clientCloseReason;

  // Server-side version triple used by [transition].
  int querySet = 0;
  int identity = 0;
  int ts = 0;

  List<Map<String, Object?>> ofType(String type) =>
      received.where((m) => m['type'] == type).toList();

  List<String> get receivedTypes => [
    for (final m in received) m['type'] as String,
  ];

  void send(Map<String, Object?> json) {
    if (closed) throw StateError('send on closed connection');
    socket.incoming.add(jsonEncode(json));
  }

  void ping() => send({'type': 'Ping'});

  /// Server-initiated close.
  void serverClose({int code = 1000, String? reason}) {
    if (closed) return;
    socket._closeCode = code;
    socket._closeReason = reason;
    closed = true;
    socket.incoming.close();
  }

  Map<String, Object?> versionMap() => {
    'querySet': querySet,
    'identity': identity,
    'ts': encodeTs(BigInt.from(ts)),
  };

  /// Sends a Transition advancing the server-side version triple.
  void transition({
    int? toQuerySet,
    int? toIdentity,
    int? toTs,
    List<Map<String, Object?>> modifications = const [],
  }) {
    final start = versionMap();
    querySet = toQuerySet ?? querySet;
    identity = toIdentity ?? identity;
    ts = toTs ?? ts;
    send({
      'type': 'Transition',
      'startVersion': start,
      'endVersion': versionMap(),
      'modifications': modifications,
    });
  }

  /// Sends the same Transition split into [parts] TransitionChunk frames.
  void chunkedTransition({
    int? toQuerySet,
    int? toIdentity,
    int? toTs,
    List<Map<String, Object?>> modifications = const [],
    required int parts,
    String transitionId = 'chunked-1',
  }) {
    final start = versionMap();
    querySet = toQuerySet ?? querySet;
    identity = toIdentity ?? identity;
    ts = toTs ?? ts;
    final payload = jsonEncode({
      'type': 'Transition',
      'startVersion': start,
      'endVersion': versionMap(),
      'modifications': modifications,
    });
    final size = (payload.length / parts).ceil();
    for (var i = 0; i < parts; i++) {
      final end = i * size + size;
      send({
        'type': 'TransitionChunk',
        'chunk': payload.substring(
          i * size,
          end > payload.length ? payload.length : end,
        ),
        'partNumber': i,
        'totalParts': parts,
        'transitionId': transitionId,
      });
    }
  }

  void respondToMutation(int requestId, Object? result, {required int ts}) {
    send({
      'type': 'MutationResponse',
      'requestId': requestId,
      'success': true,
      'result': result,
      'ts': encodeTs(BigInt.from(ts)),
      'logLines': <String>[],
    });
  }

  void failMutation(int requestId, String message, {Object? errorData}) {
    send({
      'type': 'MutationResponse',
      'requestId': requestId,
      'success': false,
      'result': message,
      'logLines': <String>[],
      'errorData': ?errorData,
    });
  }

  void respondToAction(int requestId, Object? result) {
    send({
      'type': 'ActionResponse',
      'requestId': requestId,
      'success': true,
      'result': result,
      'logLines': <String>[],
    });
  }

  void failAction(int requestId, String message, {Object? errorData}) {
    send({
      'type': 'ActionResponse',
      'requestId': requestId,
      'success': false,
      'result': message,
      'logLines': <String>[],
      'errorData': ?errorData,
    });
  }

  void authError(
    String error, {
    int? baseVersion,
    bool authUpdateAttempted = true,
  }) {
    send({
      'type': 'AuthError',
      'error': error,
      'baseVersion': ?baseVersion,
      'authUpdateAttempted': authUpdateAttempted,
    });
  }

  void fatal(String error) => send({'type': 'FatalError', 'error': error});

  /// Confirms the latest Authenticate by advancing the identity version.
  void confirmAuth({int? toTs}) =>
      transition(toIdentity: identity + 1, toTs: toTs);
}

class FakeConvexServer {
  final List<FakeConnection> connections = [];
  int connectAttempts = 0;

  /// Fail the next N connection attempts with an error.
  int refuseNext = 0;

  /// Leave the next N connection attempts hanging forever.
  int hangNext = 0;

  /// Delay successful handshakes by this much.
  Duration? handshakeDelay;

  Map<String, String>? lastHeaders;

  FakeConnection get latest => connections.last;

  Future<ConvexWebSocket> connect(Uri uri, Map<String, String> headers) {
    connectAttempts++;
    lastHeaders = headers;
    if (hangNext > 0) {
      hangNext--;
      return Completer<ConvexWebSocket>().future;
    }
    if (refuseNext > 0) {
      refuseNext--;
      return Future.error(Exception('connection refused'));
    }
    final connection = FakeConnection();
    connections.add(connection);
    final delay = handshakeDelay;
    if (delay == null) return Future.value(connection.socket);
    return Future.delayed(delay, () => connection.socket);
  }
}

ConvexClientConfig testConfig({
  Duration? defaultOperationTimeout = const Duration(seconds: 30),
  Duration? defaultConnectTimeout,
  int? maxReconnectAttempts,
  Duration authRetryInterval = const Duration(seconds: 60),
  Duration authFetchTimeout = const Duration(seconds: 15),
}) => ConvexClientConfig(
  deploymentUrl: 'https://fake.convex.cloud',
  clientId: 'dart-test-0.0.0',
  defaultOperationTimeout: defaultOperationTimeout,
  defaultConnectTimeout: defaultConnectTimeout,
  maxReconnectAttempts: maxReconnectAttempts,
  authRetryInterval: authRetryInterval,
  authFetchTimeout: authFetchTimeout,
);

class Harness {
  Harness(this.server, this.client);

  final FakeConvexServer server;
  final ConvexClient client;

  final List<ConvexClientEvent> events = [];
  final List<ConnectionSnapshot> connectionSnapshots = [];
  final List<AuthState> authStates = [];
}

/// Builds a client against a fresh fake server and drives it to `ready`.
Harness makeClient(
  FakeAsync fake, {
  ConvexClientConfig? config,
  HttpPoster? httpPoster,
  FakeConvexServer? server,
}) {
  final fakeServer = server ?? FakeConvexServer();
  final client = ConvexClient(
    config ?? testConfig(),
    socketFactory: fakeServer.connect,
    httpPoster: httpPoster,
    random: FixedRandom(),
    sessionId: 'session-1',
  );
  final harness = Harness(fakeServer, client);
  client.onEvent(harness.events.add);
  client.connectionState.listen(harness.connectionSnapshots.add);
  client.authState.listen(harness.authStates.add);
  fake.flushMicrotasks();
  return harness;
}

/// A JWT whose `exp` is relative to the (fake) clock.
String makeJwt({Duration ttl = const Duration(hours: 24), String sub = 'u1'}) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp = clock.now().add(ttl).millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'RS256', 'typ': 'JWT'})}.'
      '${part({'sub': sub, 'exp': exp})}.sig';
}

/// Records the outcome of a future without letting it become an unhandled
/// async error inside fakeAsync.
class FutureProbe<T> {
  FutureProbe(Future<T> future) {
    future.then(
      (value) {
        isDone = true;
        this.value = value;
      },
      onError: (Object e) {
        isDone = true;
        error = e;
      },
    );
  }

  bool isDone = false;
  T? value;
  Object? error;
}
