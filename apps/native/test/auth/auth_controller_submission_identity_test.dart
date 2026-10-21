import 'dart:async';
import 'dart:convert';

import 'package:app/auth/auth_controller.dart';
import 'package:app/convex/convex_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _localAccountId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

/// Only the auth surface `AuthController` touches; the test drives
/// [authStates] the way server confirmations would.
class _StubConvexClient implements ConvexClient {
  final authStates = StreamController<AuthState>.broadcast();

  @override
  Stream<AuthState> get authState => authStates.stream;

  @override
  void setAuth({required TokenFetcher fetchToken}) {}

  @override
  void clearAuth() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<AuthController> _load(
  _StubConvexClient convex,
  Map<String, Object?> account,
) async {
  FlutterSecureStorage.setMockInitialValues({
    'accounts': jsonEncode([account]),
    'active_account_id': account['id']! as String,
  });
  final auth = AuthController(convex: convex);
  await auth.load();
  return auth;
}

void main() {
  late _StubConvexClient convex;

  setUp(() => convex = _StubConvexClient());
  tearDown(() => convex.authStates.close());

  test('a local account returns its id without waiting', () async {
    final auth = await _load(convex, {
      'id': 'local_1',
      'type': 'local',
      'localAccountId': _localAccountId,
    });

    final id = await auth
        .localAccountIdForSubmission(timeout: const Duration(hours: 1))
        .timeout(const Duration(seconds: 1));

    expect(id, _localAccountId);
    auth.dispose();
  });

  test('a remote account waits for its session to authenticate', () async {
    final auth = await _load(convex, {
      'id': 'user_1',
      'type': 'remote',
      'sessionToken': 'session',
    });

    var resolved = false;
    final pending = auth
        .localAccountIdForSubmission(timeout: const Duration(hours: 1))
        .then((id) {
          resolved = true;
          return id;
        });
    await pumpEventQueue();
    expect(resolved, isFalse);

    convex.authStates.add(AuthState.authenticated);
    final id = await pending.timeout(const Duration(seconds: 1));

    expect(id, isNull);
    expect(auth.convexAuthenticated, isTrue);
    auth.dispose();
  });

  test('a remote account sends anyway once the wait runs out', () async {
    final auth = await _load(convex, {
      'id': 'user_1',
      'type': 'remote',
      'sessionToken': 'session',
    });

    final id = await auth
        .localAccountIdForSubmission(timeout: const Duration(milliseconds: 50))
        .timeout(const Duration(seconds: 1));

    expect(id, isNull);
    expect(auth.convexAuthenticated, isFalse);
    auth.dispose();
  });

  test('a remote account already known dead does not wait', () async {
    final auth = await _load(convex, {
      'id': 'user_1',
      'type': 'remote',
      'sessionToken': 'session',
      'requiresReauth': true,
    });

    final id = await auth
        .localAccountIdForSubmission(timeout: const Duration(hours: 1))
        .timeout(const Duration(seconds: 1));

    expect(id, isNull);
    auth.dispose();
  });
}
