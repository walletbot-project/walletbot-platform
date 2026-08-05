import 'dart:async';
import 'dart:convert';

import 'package:app/app_config/app_config_controller.dart';
import 'package:app/app_config/client_info.dart';
import 'package:app/auth/account.dart';
import 'package:app/config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUpAll(() {
    AppConfig.setRuntimeUrls(
      backendUrl: 'https://backend.test',
      siteUrl: 'https://site.test',
    );
  });

  test('sends locale with device and account config requests', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        request.method == 'GET'
            ? jsonEncode({
                'supported': true,
                'updateAvailable': false,
                'banners': <Object?>[],
              })
            : jsonEncode({'banners': <Object?>[]}),
        200,
      );
    });
    final controller = AppConfigController(
      clientInfo: const ClientInfo(
        platform: 'android',
        appVersion: '0.1.0',
        deviceId: 'test-device',
      ),
      httpClient: client,
      locale: 'es_AR',
    );
    addTearDown(controller.dispose);

    await controller.load();
    await controller.loadAccount(
      const UserAccount(id: 'local-1', type: AccountType.local, name: 'Local'),
    );

    final deviceRequest = requests.singleWhere(
      (request) => request.method == 'GET',
    );
    expect(deviceRequest.url.queryParameters['locale'], 'es-AR');
    expect(deviceRequest.headers['accept-language'], 'es-AR');
    expect(
      await const FlutterSecureStorage().read(
        key: 'native_config_verdict_es-AR',
      ),
      isNotNull,
    );

    final accountRequest = requests.singleWhere(
      (request) => request.method == 'POST',
    );
    final accountBody = jsonDecode(accountRequest.body) as Map<String, Object?>;
    expect(accountBody['locale'], 'es-AR');
    expect(accountRequest.headers['accept-language'], 'es-AR');
  });

  test('changing locale refetches config for the same account', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final accountLocales = <String?>[];
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        accountLocales.add(body['locale'] as String?);
      }
      return http.Response(jsonEncode({'banners': <Object?>[]}), 200);
    });
    final controller = AppConfigController(
      clientInfo: const ClientInfo(
        platform: 'android',
        appVersion: '0.1.0',
        deviceId: 'test-device',
      ),
      httpClient: client,
      locale: 'es-AR',
    );
    addTearDown(controller.dispose);
    const account = UserAccount(
      id: 'local-1',
      type: AccountType.local,
      name: 'Local',
    );

    await controller.loadAccount(account);
    expect(controller.updateLocale('en-US'), isTrue);
    await controller.loadAccount(account);

    expect(accountLocales, ['es-AR', 'en-US']);
  });

  test('changing locale drops stale localized server banners', () async {
    FlutterSecureStorage.setMockInitialValues({});
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      if (requestCount > 1) return http.Response('', 503);
      return http.Response(
        jsonEncode({
          'supported': true,
          'updateAvailable': false,
          'banners': [
            {
              'key': 'localized-notice',
              'index': 0,
              'placements': ['home'],
              'tone': 'info',
              'title': 'Aviso en español',
              'messageMarkdown': 'Contenido en español',
              'actions': <Object?>[],
            },
          ],
        }),
        200,
      );
    });
    final controller = AppConfigController(
      clientInfo: const ClientInfo(
        platform: 'android',
        appVersion: '0.1.0',
        deviceId: 'test-device',
      ),
      httpClient: client,
      locale: 'es-AR',
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.banners.single.title, 'Aviso en español');

    expect(controller.updateLocale('en-US'), isTrue);
    expect(controller.banners, isEmpty);
    await controller.load();

    expect(controller.banners, isEmpty);
  });

  test(
    'an old account response cannot overwrite a newer locale request',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final responses = <Completer<http.Response>>[];
      final client = MockClient((request) {
        final response = Completer<http.Response>();
        responses.add(response);
        return response.future;
      });
      final controller = AppConfigController(
        clientInfo: const ClientInfo(
          platform: 'android',
          appVersion: '0.1.0',
          deviceId: 'test-device',
        ),
        httpClient: client,
        locale: 'en-US',
      );
      addTearDown(controller.dispose);
      const account = UserAccount(
        id: 'local-1',
        type: AccountType.local,
        name: 'Local',
      );

      final oldRequest = controller.loadAccount(account);
      await Future<void>.delayed(Duration.zero);
      controller.updateLocale('es-AR');
      controller.updateLocale('en-US');
      final newRequest = controller.loadAccount(account);
      await Future<void>.delayed(Duration.zero);

      responses[1].complete(_accountBannerResponse('New response'));
      await newRequest;
      responses[0].complete(_accountBannerResponse('Old response'));
      await oldRequest;

      expect(controller.banners.single.title, 'New response');
    },
  );
}

http.Response _accountBannerResponse(String title) => http.Response(
  jsonEncode({
    'banners': [
      {
        'key': 'account-notice',
        'index': 0,
        'placements': ['home'],
        'tone': 'info',
        'title': title,
        'messageMarkdown': title,
        'actions': <Object?>[],
      },
    ],
  }),
  200,
);
