import 'package:app/app_config/client_info.dart';
import 'package:app/auth/promotion_carryover.dart';
import 'package:app/database.dart';
import 'package:app/legal/legal_versions.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const accountId = 'local-account';
  const clientInfo = ClientInfo(
    platform: 'ios',
    appVersion: '0.4.0',
    deviceId: 'device',
  );
  late AppDatabase db;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<Map<String, Object?>> build() => buildPromotionCarryover(
    database: db,
    accountId: accountId,
    clientInfo: clientInfo,
    locale: 'es-AR',
    versions: LegalVersions.bundled,
  );

  Future<void> accept(LegalDocumentKind document, String version) => db
      .into(db.legalAcceptances)
      .insert(
        LegalAcceptancesCompanion.insert(
          id: '${document.name}-$version',
          document: document,
          version: version,
          acceptedAt: BigInt.from(1),
          ageConfirmed: const Value(true),
          platform: 'ios',
          source: LegalAcceptanceSource.local,
        ),
      );

  test('carries nothing for an account that decided nothing', () async {
    expect(await build(), isEmpty);
  });

  test('carries the terms, AI consent and currency it settled', () async {
    final versions = LegalVersions.bundled;
    await accept(LegalDocumentKind.terms, versions.terms.current);
    await accept(LegalDocumentKind.privacy, versions.privacy.current);
    FlutterSecureStorage.setMockInitialValues({
      'ai_consent:$accountId': aiConsentVersion,
      'default_currency_$accountId': 'USD',
    });

    final carryover = await build();

    expect(carryover['acceptance'], {
      'documents': ['terms', 'privacy'],
      'ageConfirmed': true,
      'platform': 'ios',
      'appVersion': '0.4.0',
      'locale': 'es-AR',
    });
    expect(carryover['aiConsent'], {
      'platform': 'ios',
      'appVersion': '0.4.0',
      'locale': 'es-AR',
    });
    expect(carryover['defaultCurrency'], 'USD');
  });

  test(
    'does not vouch for a text older than the one this build shows',
    () async {
      await accept(LegalDocumentKind.terms, '2000-01-01');
      FlutterSecureStorage.setMockInitialValues({
        'ai_consent:$accountId': '2000-01-01',
      });

      expect(await build(), isEmpty);
    },
  );

  test('another account\'s device state is not carried', () async {
    FlutterSecureStorage.setMockInitialValues({
      'ai_consent:someone-else': aiConsentVersion,
      'default_currency_someone-else': 'USD',
    });

    expect(await build(), isEmpty);
  });
}
