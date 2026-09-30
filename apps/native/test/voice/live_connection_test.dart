import 'dart:async';
import 'dart:convert';

import 'package:app/voice/live_connection.dart';
import 'package:app/voice/live_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeSocket implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  final outgoing = <Map<String, dynamic>>[];
  final handshake = Completer<void>();
  late final FakeSink output = FakeSink(outgoing);
  void receive(Map<String, dynamic> message) =>
      incoming.add(jsonEncode(message));
  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  WebSocketSink get sink => output;
  @override
  Future<void> get ready => handshake.future;
  @override
  int? get closeCode => 1006;
  @override
  String? get closeReason => 'lost network';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSink implements WebSocketSink {
  FakeSink(this.messages);
  final List<Map<String, dynamic>> messages;
  bool closed = false;
  @override
  void add(dynamic data) {
    if (closed) throw StateError('closed');
    messages.add((jsonDecode(data as String) as Map).cast<String, dynamic>());
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'application message failures do not reconnect a healthy socket',
    () async {
      final socket = FakeSocket()..handshake.complete();
      final errors = <Object>[];
      final connection = LiveConnection(
        credentials: () async => const LiveToken('token'),
        onMessage: (message, _) {
          if (!message.containsKey('setupComplete')) {
            throw const FormatException('bad audio');
          }
        },
        onMessageError: errors.add,
        onState: (_) {},
        onError: (error) => fail('$error'),
        beforeReady: () async => null,
        connectSocket: (_) => socket,
      );
      final opening = connection.connect();
      await tick();
      socket.receive({'setupComplete': {}});
      await opening;
      final epoch = connection.epoch;
      socket.receive({'serverContent': {}});
      await tick();
      expect(errors.single, isA<FormatException>());
      expect(connection.ready, true);
      expect(connection.epoch, epoch);
      await connection.close();
      await socket.incoming.close();
    },
  );
  test(
    'waits for socket and setup, then seeds context before admitting input',
    () async {
      final socket = FakeSocket();
      final states = <LiveConnectionState>[];
      final connection = LiveConnection(
        credentials: () async => const LiveToken('test-token'),
        onMessage: (_, _) {},
        onState: states.add,
        onError: (error) => fail('$error'),
        beforeReady: () async => 'previous conversation',
        connectSocket: (_) => socket,
      );
      final opening = connection.connect();
      await tick();
      expect(socket.outgoing, isEmpty);
      expect(connection.send(LiveProtocol.text('too early')), isFalse);
      socket.handshake.complete();
      await tick();
      expect(socket.outgoing.single.containsKey('setup'), isTrue);
      expect(connection.ready, isFalse);
      socket.receive({'setupComplete': {}});
      await opening;
      expect(socket.outgoing.last['clientContent']['turnComplete'], isFalse);
      expect(connection.send(LiveProtocol.text('hello')), isTrue);
      expect(states.last, LiveConnectionState.ready);
      await connection.close();
      await socket.incoming.close();
    },
  );

  test(
    'uses the model paired with each token, including after reconnect',
    () async {
      final sockets = <FakeSocket>[];
      var model = LiveToken.legacyModel;
      final connection = LiveConnection(
        credentials: () async => LiveToken('test-token', model: model),
        onMessage: (_, _) {},
        onState: (_) {},
        onError: (error) => fail('$error'),
        beforeReady: () async => null,
        connectSocket: (_) {
          final socket = FakeSocket()..handshake.complete();
          sockets.add(socket);
          return socket;
        },
      );
      for (final selected in [LiveToken.legacyModel, 'gemini-3.8-live']) {
        model = selected;
        final opening = sockets.isEmpty
            ? connection.connect()
            : connection.reconnect();
        await tick();
        expect(
          sockets.last.outgoing.single['setup']['model'],
          'models/$selected',
        );
        sockets.last.receive({'setupComplete': {}});
        await opening;
        expect(connection.model, selected);
      }
      await connection.close();
      for (final socket in sockets) {
        await socket.incoming.close();
      }
    },
  );

  test('stop during token fetch cannot create a late socket', () async {
    final token = Completer<LiveToken>();
    var opens = 0;
    final connection = LiveConnection(
      credentials: () => token.future,
      onMessage: (_, _) {},
      onState: (_) {},
      onError: (_) {},
      beforeReady: () async => null,
      connectSocket: (_) {
        opens++;
        return FakeSocket();
      },
    );
    final opening = connection.connect();
    await tick();
    await connection.close();
    token.complete(const LiveToken('test-token'));
    await opening;
    expect(opens, 0);
    expect(connection.state, LiveConnectionState.closed);
  });

  test(
    'reconnect rejects old tool results and ignores late old messages',
    () async {
      final sockets = <FakeSocket>[];
      final received = <Map<String, dynamic>>[];
      final connection = LiveConnection(
        credentials: () async => const LiveToken('test-token'),
        onMessage: (message, _) => received.add(message),
        onState: (_) {},
        onError: (_) {},
        beforeReady: () async => null,
        connectSocket: (_) {
          final socket = FakeSocket();
          sockets.add(socket);
          return socket;
        },
      );
      Future<void> establish(Future<void> opening) async {
        await tick();
        sockets.last.handshake.complete();
        await tick();
        sockets.last.receive({'setupComplete': {}});
        await opening;
      }

      await establish(connection.connect());
      final oldEpoch = connection.epoch;
      await establish(connection.reconnect());
      sockets.first.receive({'stale': true});
      await tick();
      expect(received.any((message) => message.containsKey('stale')), isFalse);
      expect(
        connection.send({'toolResponse': {}}, expectedEpoch: oldEpoch),
        isFalse,
      );
      expect(sockets.last.outgoing, hasLength(1));
      await connection.close();
      for (final socket in sockets) {
        await socket.incoming.close();
      }
    },
  );

  test('setup timeout tears down socket without making it ready', () async {
    final socket = FakeSocket()..handshake.complete();
    final errors = <Object>[];
    final connection = LiveConnection(
      credentials: () async => const LiveToken('test-token'),
      onMessage: (_, _) {},
      onState: (_) {},
      onError: errors.add,
      beforeReady: () async => null,
      connectSocket: (_) => socket,
      setupTimeout: const Duration(milliseconds: 10),
    );
    await connection.connect();
    expect(errors.single, isA<TimeoutException>());
    expect(connection.ready, isFalse);
    await connection.close();
    await socket.incoming.close();
  });
}
