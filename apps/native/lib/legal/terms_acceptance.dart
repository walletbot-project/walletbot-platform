import 'dart:convert';

import 'package:app/sync/wire.dart';
import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Mirror of `CURRENT_LEGAL_VERSION` in `packages/shared/src/legal.ts` — the
/// "Última actualización" date shared by the four documents in `docs/legal/`.
/// Bump both together when the documents change in a way that requires
/// re-acceptance; users are re-prompted when their recorded version differs.
const currentLegalVersion = '2026-08-06';

/// Published legal pages, matching `legalUrls` in
/// `packages/shared/src/legal.ts`.
String legalTermsUrl(String localeName) =>
    'https://www.walletbot.live/${_legalLocale(localeName)}/terms';

String legalPrivacyUrl(String localeName) =>
    'https://www.walletbot.live/${_legalLocale(localeName)}/privacy';

String _legalLocale(String localeName) =>
    localeName.toLowerCase().startsWith('es') ? 'es' : 'en';

/// Device-side acceptance record. For local accounts this is the canonical
/// record (there is no backend user); for remote accounts it caches the
/// server-side row in `termsAcceptances` so launches stay quiet offline.
/// Secure storage, not the per-user drift DB: the DB is torn down and
/// recreated on account switch and this must survive that.
String termsAcceptanceCacheKey(String accountId) =>
    'terms_acceptance_$accountId';

Future<void> writeTermsAcceptanceRecord(
  FlutterSecureStorage storage, {
  required String accountId,
  required String documentVersion,
}) async {
  await storage.write(
    key: termsAcceptanceCacheKey(accountId),
    value: jsonEncode({
      'documentVersion': documentVersion,
      'acceptedAt': DateTime.now().millisecondsSinceEpoch,
    }),
  );
}

/// How the acceptance gate currently stands for the active account.
enum TermsGateStatus {
  /// No verdict yet (remote account whose server check hasn't answered).
  /// The app stays usable — offline-first: only a definitive "not accepted"
  /// ever blocks.
  unknown,

  /// No acceptance on record for [currentLegalVersion]: block until the user
  /// affirmatively accepts. Merely having shown the documents never counts.
  required,

  /// Acceptance on record — device-side for local accounts, server-side
  /// (cached on device) for remote ones.
  cleared,
}

/// Per-account acceptance state of the legal documents, modeled on
/// [DefaultCurrencyController]: cache-first, per-account secure-storage key,
/// created in the account-scoped provider subtree so nothing leaks across
/// account switches, and network I/O gated to remote accounts.
class TermsAcceptanceController extends ChangeNotifier {
  TermsAcceptanceController({
    required this.accountId,
    required this.isRemote,
    ConvexClient? client,
    FlutterSecureStorage? storage,
  }) : _client = client,
       _storage = storage ?? const FlutterSecureStorage();

  final String accountId;
  final bool isRemote;
  // Resolved lazily — only ever touched when `isRemote` is true — so local
  // accounts (and widget tests) never require `ConvexClient.initialize()`.
  final ConvexClient? _client;
  ConvexClient get _resolvedClient => _client ?? ConvexClient.instance;
  final FlutterSecureStorage _storage;

  TermsGateStatus _status = TermsGateStatus.unknown;
  TermsGateStatus get status => _status;

  /// One server round-trip per controller life: a failed check fails open
  /// and retries on the next app launch, never in a loop.
  bool _serverChecked = false;

  /// Restores the device record. A record for the current version clears the
  /// gate with no network I/O. A local account without one must accept
  /// (recording is device-side, so the gate works fully offline); a remote
  /// account stays [TermsGateStatus.unknown] until [checkRemote] gets a
  /// server verdict, so an offline launch never blocks.
  Future<void> load() async {
    try {
      final raw = await _storage.read(key: termsAcceptanceCacheKey(accountId));
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map &&
            decoded['documentVersion'] == currentLegalVersion) {
          _setStatus(TermsGateStatus.cleared);
          return;
        }
      }
    } catch (e) {
      debugPrint('terms: read cache failed: $e');
    }
    if (!isRemote) {
      _setStatus(TermsGateStatus.required);
    }
  }

  /// Asks the backend whether this account accepted the current documents.
  /// Call once Convex auth is attached. Network failure keeps the status
  /// [TermsGateStatus.unknown] — the app stays usable and the next launch
  /// retries.
  Future<void> checkRemote() async {
    if (!isRemote || _serverChecked || _status == TermsGateStatus.cleared) {
      return;
    }
    _serverChecked = true;
    try {
      final raw = await _resolvedClient.query(
        'v1/legal/queries:getMyAcceptance',
        {},
      );
      final decoded = decodeConvexResponse(raw);
      if (decoded is! Map) return;
      if (decoded['accepted'] == true) {
        await writeTermsAcceptanceRecord(
          _storage,
          accountId: accountId,
          documentVersion: currentLegalVersion,
        );
        _setStatus(TermsGateStatus.cleared);
      } else {
        _setStatus(TermsGateStatus.required);
      }
    } catch (e) {
      debugPrint('terms: acceptance check failed: $e');
    }
  }

  /// Records the user's affirmative acceptance from the gate screen:
  /// server-side for remote accounts (then cached), device-side for local
  /// ones. Throws on failure so the screen can surface it.
  Future<void> accept() async {
    if (isRemote) {
      await _resolvedClient.mutation(
        name: 'v1/legal/mutations:accept',
        args: {'documentVersion': currentLegalVersion},
      );
    }
    await writeTermsAcceptanceRecord(
      _storage,
      accountId: accountId,
      documentVersion: currentLegalVersion,
    );
    _setStatus(TermsGateStatus.cleared);
  }

  void _setStatus(TermsGateStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }
}
