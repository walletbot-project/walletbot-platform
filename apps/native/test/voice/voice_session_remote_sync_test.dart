import 'dart:async';

import 'package:app/convex/convex_client.dart';
import 'package:app/database.dart';
import 'package:app/voice/voice_session_remote_sync.dart';
import 'package:app/voice/voice_session_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('joining an in-flight flush never surfaces the sync error', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = VoiceSessionRepository(db, remoteEnabled: true);
    final session = await repository.openOrCreate(model: 'test-model');
    await repository.appendEvent(
      sessionId: session.id,
      occurredAt: DateTime.now(),
      type: 'system',
      direction: 'local',
    );

    final gate = Completer<Object?>();
    final mutationAwaited = Completer<void>();
    final sync = VoiceSessionRemoteSync(
      repository: repository,
      ownerId: 'owner-1',
      client: _StubConvexClient((name, args) {
        if (!mutationAwaited.isCompleted) mutationAwaited.complete();
        return gate.future;
      }),
    );
    addTearDown(sync.dispose);

    // First call owns the drain (blocked on the pending mutation); the
    // second joins it, like stop() flushing while a scheduled sync runs.
    final owner = sync.flush();
    final joined = sync.flush();

    // Fail the mutation only once the drain is awaiting it, like a real
    // Convex operation timeout.
    await mutationAwaited.future;
    gate.completeError(
      TimeoutException('Future not completed', const Duration(seconds: 30)),
    );

    await expectLater(joined, completes);
    await expectLater(owner, completes);
  });

  test(
    'replication mutations carry a connect bound so a drain can end',
    () async {
      // Without it the Convex client queues a mutation composed during a
      // reconnect backoff with no timer at all, and the drain that owns it
      // never returns. The outbox rows are the retry, so waiting buys nothing.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = VoiceSessionRepository(db, remoteEnabled: true);
      final session = await repository.openOrCreate(model: 'test-model');
      await repository.appendEvent(
        sessionId: session.id,
        occurredAt: DateTime.now(),
        type: 'system',
        direction: 'local',
      );

      CallOptions? seen;
      final sync = VoiceSessionRemoteSync(
        repository: repository,
        ownerId: 'owner-1',
        client: _StubConvexClient(
          (name, args) async => null,
          onOptions: (o) => seen = o,
        ),
      );
      addTearDown(sync.dispose);

      await sync.flush();
      expect(seen?.connectTimeout, isNotNull);
      expect(
        seen!.connectTimeout,
        lessThanOrEqualTo(const Duration(seconds: 15)),
      );
    },
  );

  test(
    'dispose does not wait out a mutation the server never answers',
    () async {
      // Ending a session or switching account runs through here. A drain
      // sitting on an unacknowledged mutation would otherwise hold teardown for
      // the client's full operation timeout.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = VoiceSessionRepository(db, remoteEnabled: true);
      final session = await repository.openOrCreate(model: 'test-model');
      await repository.appendEvent(
        sessionId: session.id,
        occurredAt: DateTime.now(),
        type: 'system',
        direction: 'local',
      );

      final never = Completer<Object?>();
      addTearDown(() => never.complete(null));
      final awaited = Completer<void>();
      final sync = VoiceSessionRemoteSync(
        repository: repository,
        ownerId: 'owner-1',
        client: _StubConvexClient((name, args) {
          if (!awaited.isCompleted) awaited.complete();
          return never.future;
        }),
      );

      unawaited(sync.flush());
      await awaited.future;

      final stopwatch = Stopwatch()..start();
      await sync.dispose().timeout(const Duration(seconds: 10));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 8)));
    },
  );
}

class _StubConvexClient implements ConvexClient {
  _StubConvexClient(this.onMutation, {this.onOptions});

  final Future<Object?> Function(String name, Map<String, Object?> args)
  onMutation;
  final void Function(CallOptions? options)? onOptions;

  @override
  Future<T> mutation<T>(
    String name,
    Map<String, Object?> args, {
    CallOptions? options,
  }) async {
    onOptions?.call(options);
    return await onMutation(name, args) as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
