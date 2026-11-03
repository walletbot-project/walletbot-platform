import 'package:app/app_config/client_info.dart';
import 'package:app/database.dart';
import 'package:app/legal/ai_consent_controller.dart';
import 'package:app/legal/legal_acceptance_payload.dart';
import 'package:app/legal/legal_versions.dart';
import 'package:app/user_settings/default_currency_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What a local account already decided on this device, as the `carryover` of
/// a promotion request.
///
/// A local account keeps its terms acceptance, its AI consent and its default
/// currency only on the device. Once it is an online account the backend is
/// the authority for all three, and without this it would hold none of them:
/// the app would ask for the terms again, the agent would be refused on iOS
/// for want of a consent row the user has already given, and the currency
/// would be reset to the default.
///
/// Each piece is omitted when it is absent or unreadable — the worst outcome
/// is the user being asked again, never a promotion that fails. The server
/// stamps its own current versions, so a document is only offered when the
/// version accepted here is the one this build shows.
Future<Map<String, Object?>> buildPromotionCarryover({
  required AppDatabase database,
  required String accountId,
  required ClientInfo? clientInfo,
  required String locale,
  required LegalVersions versions,
  FlutterSecureStorage? storage,
}) async {
  final secureStorage = storage ?? const FlutterSecureStorage();
  final platform = clientInfo?.platform ?? clientPlatform();
  final carryover = <String, Object?>{};

  try {
    final rows = await database.select(database.legalAcceptances).get();
    final documents = [
      for (final document in LegalDocumentKind.values)
        if (rows.any(
          (row) =>
              row.document == document &&
              row.ageConfirmed &&
              isLegalVersionAtLeast(row.version, versions.of(document).current),
        ))
          document,
    ];
    if (documents.isNotEmpty) {
      carryover['acceptance'] = LegalAcceptancePayload(
        documents: documents,
        ageConfirmed: true,
        platform: platform,
        appVersion: clientInfo?.appVersion,
        locale: locale,
      ).toJson();
    }
  } catch (e) {
    debugPrint('promotion: reading local acceptances failed: $e');
  }

  try {
    final consent = await secureStorage.read(
      key: AiConsentController.storageKey(accountId),
    );
    if (consent != null && isLegalVersionAtLeast(consent, aiConsentVersion)) {
      carryover['aiConsent'] = {
        'platform': platform,
        if (clientInfo != null) 'appVersion': clientInfo.appVersion,
        'locale': locale,
      };
    }
  } catch (e) {
    debugPrint('promotion: reading AI consent failed: $e');
  }

  try {
    final currency = await secureStorage.read(
      key: DefaultCurrencyController.cacheKey(accountId),
    );
    if (currency != null && currency.isNotEmpty) {
      carryover['defaultCurrency'] = currency;
    }
  } catch (e) {
    debugPrint('promotion: reading default currency failed: $e');
  }

  return carryover;
}
