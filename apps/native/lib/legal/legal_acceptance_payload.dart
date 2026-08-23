import 'package:app/database.dart' show LegalDocumentKind;
import 'package:flutter/foundation.dart';

/// The acceptance a sign-up form collected, as posted alongside
/// `/auth/email/sign-up`.
///
/// Email sign-up creates the account but mints no session (verification is
/// required), so there is no authenticated caller that could run
/// `v1/legal/mutations:accept` afterwards — the acceptance has to travel with
/// the sign-up request and is recorded server-side against the created user.
///
/// Carries no version: the backend stamps its own `current`, so a client
/// cannot claim to have accepted a text it was never shown.
@immutable
class LegalAcceptancePayload {
  const LegalAcceptancePayload({
    required this.documents,
    required this.ageConfirmed,
    required this.platform,
    this.appVersion,
    this.locale,
  });

  final List<LegalDocumentKind> documents;
  final bool ageConfirmed;
  final String platform;
  final String? appVersion;
  final String? locale;

  Map<String, Object?> toJson() => {
    'documents': documents.map((document) => document.name).toList(),
    'ageConfirmed': ageConfirmed,
    'platform': platform,
    if (appVersion != null) 'appVersion': appVersion,
    if (locale != null) 'locale': locale,
  };
}
