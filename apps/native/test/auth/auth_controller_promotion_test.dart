import 'dart:convert';

import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// No ConvexClient is wired, so auth attach/detach are no-ops, and the frame the
// promotion waits for is replaced by an immediate future.
void main() {
  setUpAll(() {
    AppConfig.setRuntimeUrls(
      backendUrl: 'https://backend.test',
      siteUrl: 'https://site.test',
    );
  });

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  final signedIn = {
    'accessToken': 'jwt',
    'refreshToken': 'session-secret',
    'user': {
      'id': 'server-user',
      'email': 'a@b.c',
      'name': 'Google Name',
      'image': null,
    },
  };

  AuthController controllerWith(
    Future<http.Response> Function(http.Request) handler,
  ) => AuthController(httpClient: MockClient(handler), awaitFrame: () async {});

  http.Response ok(Map<String, Object?> body) =>
      http.Response(jsonEncode(body), 200);

  test(
    'promotes in place: same id and database, remote type, server identity',
    () async {
      late Map<String, Object?> sent;
      final auth = controllerWith((request) async {
        sent = jsonDecode(request.body) as Map<String, Object?>;
        return ok(signedIn);
      });
      final local = await auth.addLocal(name: 'Mine');
      final order = <String>[];
      final promotingDuringConvert = <String?>[];
      auth.addListener(() => promotingDuringConvert.add(auth.promotingId));

      final promoted = await auth.signInWithEmail(
        email: 'a@b.c',
        password: 'password123',
        promotion: LocalPromotion(
          accountId: local.id,
          beforeConvert: () async {
            // Still the local account while the caller flags its rows.
            order.add('before:${auth.activeAccount!.type.name}');
          },
        ),
      );

      expect(sent['promoteLocalAccountId'], local.localAccountId);
      expect(order, ['before:local']);
      expect(promoted.id, local.id);
      expect(promoted.type, AccountType.remote);
      expect(promoted.remoteUserId, 'server-user');
      expect(promoted.serverUserId, 'server-user');
      expect(promoted.sessionToken, 'session-secret');
      // The name the user chose wins over the provider's.
      expect(promoted.name, 'Mine');
      expect(promoted.email, 'a@b.c');
      expect(auth.accounts, hasLength(1));
      expect(auth.activeId, local.id);
      // The placeholder frame was requested, then released.
      expect(promotingDuringConvert.first, local.id);
      expect(auth.promotingId, isNull);

      final reloaded = AuthController();
      await reloaded.load();
      expect(reloaded.accounts.single.remoteUserId, 'server-user');
      expect(reloaded.accounts.single.type, AccountType.remote);
      expect(reloaded.accounts.single.id, local.id);
    },
  );

  test('sends what the local account settled along with the request', () async {
    late Map<String, Object?> sent;
    final auth = controllerWith((request) async {
      sent = jsonDecode(request.body) as Map<String, Object?>;
      return ok(signedIn);
    });
    final local = await auth.addLocal(name: 'Mine');

    await auth.signInWithEmail(
      email: 'a@b.c',
      password: 'password123',
      promotion: LocalPromotion(
        accountId: local.id,
        beforeConvert: () async {},
        carryover: const {'defaultCurrency': 'USD'},
      ),
    );

    expect(sent['carryover'], {'defaultCurrency': 'USD'});
  });

  test('sends no carryover key when there is nothing to carry', () async {
    late Map<String, Object?> sent;
    final auth = controllerWith((request) async {
      sent = jsonDecode(request.body) as Map<String, Object?>;
      return ok(signedIn);
    });
    final local = await auth.addLocal(name: 'Mine');

    await auth.signInWithEmail(
      email: 'a@b.c',
      password: 'password123',
      promotion: LocalPromotion(
        accountId: local.id,
        beforeConvert: () async {},
      ),
    );

    expect(sent.containsKey('carryover'), isFalse);
  });

  test('a refused promotion leaves the local account untouched', () async {
    final auth = controllerWith(
      (_) async => http.Response(
        jsonEncode({'code': 'account_exists', 'message': 'exists'}),
        409,
      ),
    );
    final local = await auth.addLocal(name: 'Mine');
    var converted = false;

    await expectLater(
      auth.signInWithEmail(
        email: 'a@b.c',
        password: 'password123',
        promotion: LocalPromotion(
          accountId: local.id,
          beforeConvert: () async => converted = true,
        ),
      ),
      throwsA(isA<AccountExistsException>()),
    );

    expect(converted, isFalse);
    expect(auth.activeAccount!.type, AccountType.local);
    expect(auth.activeAccount!.sessionToken, isNull);
    expect(auth.promotingId, isNull);
  });

  test('a failure preparing the data aborts the conversion', () async {
    final auth = controllerWith((_) async => ok(signedIn));
    final local = await auth.addLocal(name: 'Mine');

    await expectLater(
      auth.signInWithEmail(
        email: 'a@b.c',
        password: 'password123',
        promotion: LocalPromotion(
          accountId: local.id,
          beforeConvert: () async => throw StateError('db busy'),
        ),
      ),
      throwsStateError,
    );

    expect(auth.activeAccount!.type, AccountType.local);
    expect(auth.promotingId, isNull);
  });

  test('refuses to duplicate a user already on the device', () async {
    final auth = controllerWith((_) async => ok(signedIn));
    // The same user signed in through the regular screen first.
    await auth.signInWithEmail(email: 'a@b.c', password: 'password123');
    final local = await auth.addLocal(name: 'Mine');

    await expectLater(
      auth.signInWithEmail(
        email: 'a@b.c',
        password: 'password123',
        promotion: LocalPromotion(
          accountId: local.id,
          beforeConvert: () async {},
        ),
      ),
      throwsA(isA<AccountAlreadyAddedError>()),
    );

    expect(auth.accounts.map((a) => a.type), [
      AccountType.remote,
      AccountType.local,
    ]);
  });

  test('promotion requires a local account', () async {
    final auth = controllerWith((_) async => ok(signedIn));
    await auth.signInWithEmail(email: 'a@b.c', password: 'password123');

    await expectLater(
      auth.signInWithEmail(
        email: 'a@b.c',
        password: 'password123',
        promotion: LocalPromotion(
          accountId: 'server-user',
          beforeConvert: () async {},
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'signing in again lands on the promoted entry instead of a second one',
    () async {
      final auth = controllerWith((_) async => ok(signedIn));
      final local = await auth.addLocal(name: 'Mine');
      await auth.signInWithEmail(
        email: 'a@b.c',
        password: 'password123',
        promotion: LocalPromotion(
          accountId: local.id,
          beforeConvert: () async {},
        ),
      );

      // Its session died and the user signs in again from the login screen.
      final again = await auth.signInWithEmail(
        email: 'a@b.c',
        password: 'password123',
      );

      expect(auth.accounts, hasLength(1));
      expect(again.id, local.id);
      expect(again.remoteUserId, 'server-user');
      expect(auth.activeId, local.id);
    },
  );

  test('token refresh identifies the user by its server id', () async {
    final bodies = <Map<String, Object?>>[];
    final auth = controllerWith((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      if (request.url.path == '/auth/refresh') {
        bodies.add(body);
        return ok({'accessToken': 'fresh'});
      }
      return ok(signedIn);
    });
    final local = await auth.addLocal(name: 'Mine');
    await auth.signInWithEmail(
      email: 'a@b.c',
      password: 'password123',
      promotion: LocalPromotion(
        accountId: local.id,
        beforeConvert: () async {},
      ),
    );

    await auth.fetchAccessTokenForHttp();

    expect(bodies.single['userId'], 'server-user');
  });
}
