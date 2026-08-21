import 'dart:convert';

import 'package:app/app_config/app_config_controller.dart';
import 'package:app/app_config/client_info.dart';
import 'package:app/config.dart';
import 'package:app/legal/terms_acceptance.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Builds an `AppConfigController` whose `/v1/config` fetch answers with
/// [legal] as its policy block, like a backend that just published new
/// documents.
AppConfigController _configServing(Map<String, Object?>? legal) {
  final client = MockClient((request) async {
    if (request.method != 'GET') {
      return http.Response(jsonEncode({'banners': <Object?>[]}), 200);
    }
    return http.Response(
      jsonEncode({
        'supported': true,
        'updateAvailable': false,
        'banners': <Object?>[],
        'legal': ?legal,
      }),
      200,
    );
  });
  return AppConfigController(
    clientInfo: const ClientInfo(
      platform: 'android',
      appVersion: '0.2.0',
      deviceId: 'test-device',
    ),
    httpClient: client,
    locale: 'es-AR',
  );
}

const _policy = LegalPolicy(
  currentVersion: '2026-08-06',
  minVersion: '2026-08-06',
  graceEndsAt: null,
);

void main() {
  setUpAll(() {
    AppConfig.setRuntimeUrls(
      backendUrl: 'https://backend.test',
      siteUrl: 'https://site.test',
    );
  });

  group('legalVerdict', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000);

    test('accepting the current documents clears the gate', () {
      expect(legalVerdict('2026-08-06', _policy, now), TermsGateStatus.cleared);
    });

    test('never accepted blocks', () {
      expect(legalVerdict(null, _policy, now), TermsGateStatus.required);
    });

    test('below the min floor blocks, with no grace', () {
      const policy = LegalPolicy(
        currentVersion: '2026-09-01',
        minVersion: '2026-08-20',
        graceEndsAt: 999999,
      );
      expect(legalVerdict('2026-08-06', policy, now), TermsGateStatus.required);
    });

    test('old but above the floor prompts while the grace runs', () {
      const policy = LegalPolicy(
        currentVersion: '2026-09-01',
        minVersion: '2026-08-06',
        graceEndsAt: 2000,
      );
      expect(
        legalVerdict('2026-08-06', policy, now),
        TermsGateStatus.requested,
      );
    });

    test('the same acceptance blocks once the grace expires', () {
      const policy = LegalPolicy(
        currentVersion: '2026-09-01',
        minVersion: '2026-08-06',
        graceEndsAt: 500,
      );
      expect(legalVerdict('2026-08-06', policy, now), TermsGateStatus.required);
    });

    test('a null grace prompts forever, never blocks', () {
      const policy = LegalPolicy(
        currentVersion: '2026-09-01',
        minVersion: '2026-08-06',
        graceEndsAt: null,
      );
      expect(
        legalVerdict(
          '2026-08-06',
          policy,
          DateTime.fromMillisecondsSinceEpoch(1 << 45),
        ),
        TermsGateStatus.requested,
      );
    });
  });

  group(
    'local accounts pick up a backend policy change in the same launch',
    () {
      Future<TermsAcceptanceController> launch(
        AppConfigController config, {
        required String acceptedVersion,
      }) async {
        FlutterSecureStorage.setMockInitialValues({});
        await writeTermsAcceptanceRecord(
          const FlutterSecureStorage(),
          accountId: 'local-1',
          documentVersion: acceptedVersion,
        );
        final terms = TermsAcceptanceController(
          accountId: 'local-1',
          isRemote: false,
          policy: () => config.legalPolicy ?? _policy,
          policyChanges: config,
        );
        await terms.load();
        return terms;
      }

      test(
        'a newer version inside the grace turns into the soft prompt',
        () async {
          final config = _configServing({
            'currentVersion': '2026-09-01',
            'minVersion': '2026-08-06',
            'graceEndsAt': 4102444800000,
          });
          addTearDown(config.dispose);
          final terms = await launch(config, acceptedVersion: '2026-08-06');
          addTearDown(terms.dispose);

          // Before config lands, the bundled policy says the record is current.
          expect(terms.status, TermsGateStatus.cleared);

          await config.load();

          expect(terms.status, TermsGateStatus.requested);
          expect(terms.currentVersion, '2026-09-01');
          expect(terms.graceEndsAt, 4102444800000);
        },
      );

      test('an expired grace blocks in the same launch', () async {
        final config = _configServing({
          'currentVersion': '2026-09-01',
          'minVersion': '2026-08-06',
          'graceEndsAt': 1,
        });
        addTearDown(config.dispose);
        final terms = await launch(config, acceptedVersion: '2026-08-06');
        addTearDown(terms.dispose);

        await config.load();

        expect(terms.status, TermsGateStatus.required);
      });

      test('an unchanged policy leaves a cleared gate alone', () async {
        final config = _configServing({
          'currentVersion': '2026-08-06',
          'minVersion': '2026-08-06',
          'graceEndsAt': null,
        });
        addTearDown(config.dispose);
        final terms = await launch(config, acceptedVersion: '2026-08-06');
        addTearDown(terms.dispose);

        await config.load();

        expect(terms.status, TermsGateStatus.cleared);
      });

      test('a malformed policy block keeps the device usable', () async {
        final config = _configServing({'currentVersion': 'not-a-date'});
        addTearDown(config.dispose);
        final terms = await launch(config, acceptedVersion: '2026-08-06');
        addTearDown(terms.dispose);

        await config.load();

        expect(config.legalPolicy, isNull);
        expect(terms.status, TermsGateStatus.cleared);
      });
    },
  );

  group('remote accounts', () {
    test('still ask the server when the device record looks current', () async {
      FlutterSecureStorage.setMockInitialValues({});
      await writeTermsAcceptanceRecord(
        const FlutterSecureStorage(),
        accountId: 'remote-1',
        documentVersion: '2026-08-06',
      );
      final terms = TermsAcceptanceController(
        accountId: 'remote-1',
        isRemote: true,
        policy: () => _policy,
      );
      addTearDown(terms.dispose);

      await terms.load();

      expect(terms.status, TermsGateStatus.cleared);
      // The cache cannot know whether the policy moved, so the launch still
      // owes the backend one question.
      expect(terms.needsServerCheck, isTrue);
    });

    test(
      'a cache-derived block is softened to the dismissible prompt',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        await writeTermsAcceptanceRecord(
          const FlutterSecureStorage(),
          accountId: 'remote-2',
          documentVersion: '2026-01-01',
        );
        final terms = TermsAcceptanceController(
          accountId: 'remote-2',
          isRemote: true,
          policy: () => _policy,
        );
        addTearDown(terms.dispose);

        await terms.load();

        // legalVerdict alone would say `required` (below the min floor), but
        // accepting needs the network: only a live server verdict may block.
        expect(terms.status, TermsGateStatus.requested);
      },
    );

    test('no device record stays unknown, so the app opens offline', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final terms = TermsAcceptanceController(
        accountId: 'remote-3',
        isRemote: true,
        policy: () => _policy,
      );
      addTearDown(terms.dispose);

      await terms.load();

      expect(terms.status, TermsGateStatus.unknown);
    });
  });
}
