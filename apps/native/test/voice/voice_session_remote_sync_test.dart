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
}

class _StubConvexClient implements ConvexClient {
  _StubConvexClient(this.onMutation);

  final Future<Object?> Function(String name, Map<String, Object?> args)
  onMutation;

  @override
  Future<T> mutation<T>(
    String name,
    Map<String, Object?> args, {
    CallOptions? options,
  }) async => await onMutation(name, args) as T;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
