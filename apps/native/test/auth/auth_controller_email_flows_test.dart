import 'dart:convert';

import 'package:app/auth/auth_controller.dart';
import 'package:app/config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// These tests only exercise error paths and the new email endpoints — no
// ConvexClient is wired, so auth attach/detach are no-ops.
void main() {
  setUpAll(() {
    AppConfig.setRuntimeUrls(
      backendUrl: 'https://backend.test',
      siteUrl: 'https://site.test',
    );
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  // Never disposed, matching widget_test.dart; without a ConvexClient the
  // detach on dispose is a no-op anyway.
  AuthController controllerWith(MockClient client) {
    return AuthController(httpClient: client);
  }

  MockClient respondWith(int statusCode, Map<String, Object?> body) {
    return MockClient(
      (request) async => http.Response(jsonEncode(body), statusCode),
    );
  }

  test('sign-in surfaces email_not_verified as typed exception, '
      'no account saved', () async {
    final auth = controllerWith(
      respondWith(403, {'code': 'email_not_verified', 'message': 'verify'}),
    );

    await expectLater(
      auth.signInWithEmail(email: 'a@b.c', password: 'password123'),
      throwsA(isA<EmailNotVerifiedException>()),
    );
    expect(auth.accounts, isEmpty);
    expect(auth.activeAccount, isNull);
  });

  test('sign-up surfaces email_not_verified as typed exception, '
      'no account saved', () async {
    final auth = controllerWith(
      respondWith(403, {'code': 'email_not_verified', 'message': 'verify'}),
    );

    await expectLater(
      auth.signUpWithEmail(name: 'A', email: 'a@b.c', password: 'password123'),
      throwsA(isA<EmailNotVerifiedException>()),
    );
    expect(auth.accounts, isEmpty);
    expect(auth.activeAccount, isNull);
  });

  test('other sign-in failures stay AuthHttpError with parsed code', () async {
    final auth = controllerWith(
      respondWith(401, {'code': 'sign_in_failed', 'message': 'nope'}),
    );

    await expectLater(
      auth.signInWithEmail(email: 'a@b.c', password: 'password123'),
      throwsA(
        isA<AuthHttpError>()
            .having((e) => e.code, 'code', 'sign_in_failed')
            .having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
    await expectLater(
      auth.signInWithEmail(email: 'a@b.c', password: 'password123'),
      throwsA(isNot(isA<EmailNotVerifiedException>())),
    );
  });

  test(
    'requestPasswordReset posts the email to /auth/password/forgot',
    () async {
      final requests = <http.Request>[];
      final auth = controllerWith(
        MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );

      await auth.requestPasswordReset(email: 'a@b.c');

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://site.test/auth/password/forgot');
      expect(jsonDecode(request.body), {'email': 'a@b.c'});
    },
  );

  test(
    'resendVerificationEmail posts to /auth/email/resend-verification',
    () async {
      final requests = <http.Request>[];
      final auth = controllerWith(
        MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );

      await auth.resendVerificationEmail(email: 'a@b.c');

      final request = requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://site.test/auth/email/resend-verification',
      );
      expect(jsonDecode(request.body), {'email': 'a@b.c'});
    },
  );

  test(
    'requestAccountDeletion posts to /v1/account-deletion/request',
    () async {
      final requests = <http.Request>[];
      final auth = controllerWith(
        MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );

      await auth.requestAccountDeletion(email: 'a@b.c');

      final request = requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://site.test/v1/account-deletion/request',
      );
      expect(jsonDecode(request.body), {'email': 'a@b.c'});
    },
  );

  test('requestPasswordReset propagates non-2xx as AuthHttpError', () async {
    final auth = controllerWith(
      respondWith(500, {'code': 'internal', 'message': 'boom'}),
    );

    await expectLater(
      auth.requestPasswordReset(email: 'a@b.c'),
      throwsA(isA<AuthHttpError>().having((e) => e.statusCode, 'status', 500)),
    );
  });
}
