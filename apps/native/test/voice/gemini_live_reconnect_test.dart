import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/voice/gemini_voice_expense_command.dart';
import 'package:app/voice/voice_event.dart';
import 'package:app/voice/voice_session_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_live_server.dart';

/// Connection lifecycle of the Gemini Live session: reconnection, context
/// restoration across a drop, backoff bounds, and what happens to input
/// recorded while the socket is gone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioChannel = MethodChannel('live.walletbot.app/pcm_audio');

  late AppDatabase db;
  late VoiceSessionRepository sessions;
  late FakeLiveServer server;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, (call) async => null);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessions = VoiceSessionRepository(db);
    server = FakeLiveServer();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, null);
    await db.close();
  });

  GeminiVoiceExpenseCommandFactory buildFactory() =>
      GeminiVoiceExpenseCommandFactory(
        repositories: AppRepositories(db),
        sessionRepository: sessions,
        socketFactory: server.connect,
        attachPlatformHooks: false,
        // A literal token skips the Convex/HTTP mint entirely.
        liveToken: 'test-live-token',
      );

  Future<GeminiVoiceExpenseCommand> start(
    GeminiVoiceExpenseCommandFactory factory,
  ) async {
    final command = factory.create() as GeminiVoiceExpenseCommand;
    await command.start();
    return command;
  }

  test('a server-side drop reconnects and reaches connected again', () async {
    final command = await start(buildFactory());
    expect(command.isConnected, isTrue);
    expect(server.connectCount, 1);

    server.latest.dropFromServer();
    await pumpEventQueue();
    expect(command.isConnected, isFalse);

    // The first backoff step is 1 s; a network hint skips it.
    command.onNetworkAvailable();
    await pumpEventQueue();

    expect(server.connectCount, 2);
    expect(command.isConnected, isTrue);
    await command.dispose();
  });

  test('the reconnect seeds the transcript even when no resumption handle ever '
      'arrived', () async {
    final command = await start(buildFactory());

    // A full exchange, and deliberately no sessionResumptionUpdate: that is
    // the case the resume-handle gate turned into total context loss.
    server.latest.sendUserTranscript('cuanto gaste en comida');
    server.latest.sendAgentTranscript('Gastaste 12.500 pesos.');
    server.latest.sendTurnComplete();
    await pumpEventQueue();

    server.latest.dropFromServer();
    await pumpEventQueue();
    command.onNetworkAvailable();
    await pumpEventQueue();

    expect(server.connectCount, 2);
    final seed = server.latest.clientTexts.first;
    expect(seed, contains('Context restore'));
    expect(seed, contains('User: cuanto gaste en comida'));
    expect(seed, contains('Assistant: Gastaste 12.500 pesos.'));
    await command.dispose();
  });

  test(
    'the seed waits for the durable log to drain, keeping the last turn',
    () async {
      final command = await start(buildFactory());

      // A burst deep enough that the repository write tail is still draining
      // when the reconnect asks for the transcript. Reading it unflushed
      // dropped the most recent turns from the seed.
      for (var i = 0; i < 40; i++) {
        server.latest.sendUserTranscript('linea $i ');
      }
      server.latest.sendAgentTranscript('Listo, cargue 3.000.');
      server.latest.sendTurnComplete();
      server.latest.dropFromServer();
      await pumpEventQueue(times: 1);
      command.onNetworkAvailable();
      await pumpEventQueue();

      final seed = server.latest.clientTexts.first;
      expect(seed, contains('linea 0'));
      expect(seed, contains('linea 39'));
      expect(seed, contains('Listo, cargue 3.000.'));
      await command.dispose();
    },
  );

  test('audio recorded while disconnected is dropped, not replayed', () async {
    final command = await start(buildFactory());
    final first = server.latest;

    server.latest.dropFromServer();
    await pumpEventQueue();

    // 30 chunks is 3 s of speech into a socket that no longer exists.
    for (var i = 0; i < 30; i++) {
      await command.addAudioChunk(Uint8List(3200));
    }
    command.onNetworkAvailable();
    await pumpEventQueue();

    expect(server.connectCount, 2);
    expect(
      server.latest.framesOfKind('realtimeInput'),
      isEmpty,
      reason: 'stale audio must not be flushed into the fresh session',
    );
    expect(first.framesOfKind('realtimeInput'), isEmpty);
    await command.dispose();
  });

  test('audio recorded while connected still reaches the server', () async {
    final command = await start(buildFactory());
    await command.addAudioChunk(Uint8List(3200));
    await pumpEventQueue();
    expect(server.latest.framesOfKind('realtimeInput'), hasLength(1));
    await command.dispose();
  });

  test(
    'a text message sent while disconnected is queued and delivered once',
    () async {
      final command = await start(buildFactory());

      server.latest.dropFromServer();
      await pumpEventQueue();
      await command.sendText('agrega 500 de cafe');
      command.onNetworkAvailable();
      await pumpEventQueue();

      final texts = server.latest.clientTexts;
      expect(texts.last, 'agrega 500 de cafe');
      expect(
        texts.where((t) => t.contains('agrega 500 de cafe')),
        hasLength(1),
        reason: 'the pending text must not also appear inside the seed',
      );
      await command.dispose();
    },
  );

  test('the reconnect backoff never collapses to zero', () {
    // Regression for the int64 wrap in `min(30, pow(2, attempt - 1).toInt())`:
    // from attempt 64 the delay went negative and then saturated at 0, turning
    // the backoff into a hot reconnect loop.
    for (var attempt = 1; attempt <= 200; attempt++) {
      final seconds = reconnectBackoffSeconds(attempt);
      expect(seconds, greaterThanOrEqualTo(1), reason: 'attempt $attempt');
      expect(seconds, lessThanOrEqualTo(30), reason: 'attempt $attempt');
    }
    expect(reconnectBackoffSeconds(1), 1);
    expect(reconnectBackoffSeconds(4), 8);
    expect(reconnectBackoffSeconds(6), 30);
    expect(reconnectBackoffSeconds(64), 30);
    expect(reconnectBackoffSeconds(1030), 30);
  });

  test(
    'a network change replaces a socket the client still believes is open',
    () async {
      final command = await start(buildFactory());
      final stale = server.latest;
      expect(command.isConnected, isTrue);

      // WiFi to cellular: nothing reports an outage, but the socket is bound
      // to a route that no longer exists.
      command.onNetworkChanged();
      await pumpEventQueue();

      expect(stale.closedByClient, isTrue);
      expect(server.connectCount, 2);
      expect(command.isConnected, isTrue);
      await command.dispose();
    },
  );

  test('goAway reconnects shortly before the announced kill', () async {
    final command = await start(buildFactory());
    server.latest.sendGoAway('2.15s');
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await pumpEventQueue();
    expect(server.connectCount, 2);
    await command.dispose();
  });

  test('explicit stop ends the session and stops reconnecting', () async {
    final command = await start(buildFactory());
    await command.stop();
    expect(command.isActive, isFalse);

    server.latest.dropFromServer();
    await pumpEventQueue();
    expect(server.connectCount, 1);
  });

  test('a resumption handle is recorded but never presented back', () async {
    final command = await start(buildFactory());
    server.latest.sendResumptionUpdate();
    await pumpEventQueue();

    server.latest.dropFromServer();
    await pumpEventQueue();
    command.onNetworkAvailable();
    await pumpEventQueue();

    final setup = server.latest.framesOfKind('setup').single;
    final resumption =
        (setup['setup']! as Map)['sessionResumption']! as Map<Object?, Object?>;
    expect(
      resumption,
      isEmpty,
      reason: 'a stale handle makes the server open a blank session',
    );
    await command.dispose();
  });

  test(
    'the conversation survives a drop for the UI restore path too',
    () async {
      final factory = buildFactory();
      final command = await start(factory);
      server.latest.sendResumptionUpdate();
      server.latest.sendUserTranscript('hola');
      server.latest.sendAgentTranscript('Hola, en que te ayudo?');
      server.latest.sendTurnComplete();
      await pumpEventQueue();

      server.latest.dropFromServer();
      await pumpEventQueue();
      await sessions.flush();

      final restored = await factory.restorableHistory();
      expect(restored.whereType<VoiceUserTranscriptDelta>(), isNotEmpty);
      expect(restored.whereType<VoiceAgentTranscriptDelta>(), isNotEmpty);
      await command.dispose();
    },
  );
}
