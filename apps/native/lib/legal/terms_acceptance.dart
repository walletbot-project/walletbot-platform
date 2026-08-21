import 'dart:convert';

import 'package:app/sync/wire.dart';
import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Bundled mirror of the legal policy in `packages/shared/src/legal.ts`.
/// The live policy travels over the wire (`/v1/config` → [LegalPolicy]); these
/// constants are only the last-resort fallback for a device that never
/// fetched config. Keep them in sync with the shared module.
const currentLegalVersion = '2026-08-06';
const minAcceptedLegalVersion = '2026-08-06';

const bundledLegalPolicy = LegalPolicy(
  currentVersion: currentLegalVersion,
  minVersion: minAcceptedLegalVersion,
  graceEndsAt: null,
);

final _legalVersionPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool isValidLegalVersion(String value) => _legalVersionPattern.hasMatch(value);

/// Published legal pages, matching `legalUrls` in
/// `packages/shared/src/legal.ts`.
String legalTermsUrl(String localeName) =>
    'https://www.walletbot.live/${_legalLocale(localeName)}/terms';

String legalPrivacyUrl(String localeName) =>
    'https://www.walletbot.live/${_legalLocale(localeName)}/privacy';

String _legalLocale(String localeName) =>
    localeName.toLowerCase().startsWith('es') ? 'es' : 'en';

/// The server-owned enforcement policy. A document version is its
/// "Última actualización" ISO date, so versions compare as strings.
@immutable
class LegalPolicy {
  const LegalPolicy({
    required this.currentVersion,
    required this.minVersion,
    required this.graceEndsAt,
  });

  /// Newest published documents — what the gate shows and records.
  final String currentVersion;

  /// Hard floor: acceptances older than this are void with no grace.
  final String minVersion;

  /// Instant (ms epoch) when old-but-≥-min acceptances stop being valid.
  /// `null` = the grace never ends (dismissible prompt forever).
  final int? graceEndsAt;

  static LegalPolicy? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final current = raw['currentVersion'];
    final min = raw['minVersion'];
    final grace = raw['graceEndsAt'];
    if (current is! String || !isValidLegalVersion(current)) return null;
    if (min is! String || !isValidLegalVersion(min)) return null;
    if (min.compareTo(current) > 0) return null;
    return LegalPolicy(
      currentVersion: current,
      minVersion: min,
      graceEndsAt: grace is num ? grace.round() : null,
    );
  }

  // Value equality: a config refresh that re-delivers the same policy must not
  // look like a policy change to [TermsAcceptanceController].
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegalPolicy &&
          other.currentVersion == currentVersion &&
          other.minVersion == minVersion &&
          other.graceEndsAt == graceEndsAt;

  @override
  int get hashCode => Object.hash(currentVersion, minVersion, graceEndsAt);
}

/// How the acceptance gate currently stands for the active account.
enum TermsGateStatus {
  /// No verdict yet (remote account with no device record and no server
  /// answer). The app stays usable — offline-first: only definitive
  /// knowledge ever blocks.
  unknown,

  /// Old-but-still-valid acceptance: show the prompt WITH a "Not now"
  /// escape. Also the rendering for any server status this build does not
  /// recognize, so a future state can never hard-block an old client.
  requested,

  /// No valid acceptance: block until the user affirmatively accepts.
  required,

  /// Acceptance of the current documents on record.
  cleared,
}

/// Mirror of `legalVerdict` in `packages/shared/src/legal.ts` — keep both in
/// sync. Callers must only pass `acceptedVersion: null` when "never accepted"
/// is a known fact (local accounts); absence of knowledge is
/// [TermsGateStatus.unknown] and never reaches this function.
TermsGateStatus legalVerdict(
  String? acceptedVersion,
  LegalPolicy policy,
  DateTime now,
) {
  if (acceptedVersion != null &&
      acceptedVersion.compareTo(policy.currentVersion) >= 0) {
    return TermsGateStatus.cleared;
  }
  if (acceptedVersion == null ||
      acceptedVersion.compareTo(policy.minVersion) < 0) {
    return TermsGateStatus.required;
  }
  final graceEndsAt = policy.graceEndsAt;
  if (graceEndsAt == null || now.millisecondsSinceEpoch < graceEndsAt) {
    return TermsGateStatus.requested;
  }
  return TermsGateStatus.required;
}

/// Device-side acceptance record. For local accounts this is the canonical
/// record (there is no backend user); for remote accounts it caches the
/// server-side row in `termsAcceptances` so offline launches can still
/// evaluate the policy. Secure storage, not the per-user drift DB: the DB is
/// torn down and recreated on account switch and this must survive that.
String termsAcceptanceCacheKey(String accountId) =>
    'terms_acceptance_$accountId';

Future<void> writeTermsAcceptanceRecord(
  FlutterSecureStorage storage, {
  required String accountId,
  required String documentVersion,
  int? acceptedAt,
}) async {
  await storage.write(
    key: termsAcceptanceCacheKey(accountId),
    value: jsonEncode({
      'documentVersion': documentVersion,
      'acceptedAt': acceptedAt ?? DateTime.now().millisecondsSinceEpoch,
    }),
  );
}

/// Per-account acceptance state of the legal documents, modeled on
/// [DefaultCurrencyController]: cache-first, per-account secure-storage key,
/// created in the account-scoped provider subtree so nothing leaks across
/// account switches, and network I/O gated to remote accounts.
///
/// Enforcement invariant (offline-first): for REMOTE accounts a verdict
/// derived from device caches is never harder than [TermsGateStatus.requested]
/// — accepting needs the network, so only a live server verdict may hard
/// block. LOCAL accounts evaluate and record entirely on-device, so their
/// gate works (and may block) with no connectivity at all.
///
/// Freshness invariant: a policy published on the backend takes effect on the
/// NEXT app launch, never the one after. Remote accounts always ask the server
/// once per launch — a device cache saying "accepted" is not a reason to skip
/// the check, because the cache cannot know the policy moved. Local accounts
/// re-evaluate whenever [policyChanges] fires with a different policy, which is
/// what the `/v1/config` fetch does moments after launch.
class TermsAcceptanceController extends ChangeNotifier {
  TermsAcceptanceController({
    required this.accountId,
    required this.isRemote,
    required LegalPolicy Function() policy,
    Listenable? policyChanges,
    ConvexClient? client,
    FlutterSecureStorage? storage,
  }) : _policy = policy,
       _policyChanges = policyChanges,
       _client = client,
       _storage = storage ?? const FlutterSecureStorage() {
    _policyChanges?.addListener(_onPolicyChanged);
  }

  final String accountId;
  final bool isRemote;

  /// Freshest device-known policy (cached `/v1/config` via
  /// `AppConfigController`, falling back to [bundledLegalPolicy]).
  final LegalPolicy Function() _policy;

  /// Notifier that fires when [_policy] may have moved — `AppConfigController`
  /// in the app, so the `/v1/config` refresh lands in the same launch.
  final Listenable? _policyChanges;

  /// Policy the current [_status] was decided against. Guards the listener
  /// above: a config refresh that re-delivers the same policy costs nothing.
  LegalPolicy? _appliedPolicy;

  // Resolved lazily — only ever touched when `isRemote` is true — so local
  // accounts (and widget tests) never require `ConvexClient.initialize()`.
  final ConvexClient? _client;
  ConvexClient get _resolvedClient => _client ?? ConvexClient.instance;
  final FlutterSecureStorage _storage;

  TermsGateStatus _status = TermsGateStatus.unknown;
  TermsGateStatus get status => _status;

  /// Newest accepted version known on this device (null = no record).
  String? _acceptedVersion;

  /// Policy values learned from the live server verdict, fresher than the
  /// config cache while this controller lives.
  String? _serverCurrentVersion;
  int? _serverGraceEndsAt;
  bool _serverPolicyKnown = false;

  /// "Not now" on the soft prompt, remembered per controller life (= per
  /// account activation / app launch) and per documents version.
  String? _dismissedVersion;
  bool get promptDismissed => _dismissedVersion == currentVersion;

  /// One server round-trip per controller life: a failed check fails open
  /// and retries on the next app launch, never in a loop. Cleared only when
  /// the policy itself moves under us (see [_onPolicyChanged]), which is a new
  /// question, not a retry.
  bool _serverChecked = false;
  bool _checking = false;
  bool _recheckQueued = false;

  /// Whether the authoritative server verdict for this launch is still
  /// outstanding. `_TermsGate` (main.dart) uses it to trigger [checkRemote]
  /// once Convex auth is attached.
  bool get needsServerCheck => isRemote && !_serverChecked;

  /// Version the gate displays and records.
  String get currentVersion =>
      _serverCurrentVersion ?? _policy().currentVersion;

  /// Deadline for the soft prompt's copy, if any.
  int? get graceEndsAt =>
      _serverPolicyKnown ? _serverGraceEndsAt : _policy().graceEndsAt;

  /// Restores the device record and evaluates the policy locally. Local
  /// accounts get their final verdict here (recording is device-side, so the
  /// gate works fully offline — a missing record IS "never accepted"). For
  /// remote accounts a missing record stays [TermsGateStatus.unknown] (fail
  /// open until [checkRemote] answers), and a cache-derived "required" is
  /// softened to [TermsGateStatus.requested] per the class invariant.
  Future<void> load() async {
    try {
      final raw = await _storage.read(key: termsAcceptanceCacheKey(accountId));
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        final version = decoded is Map ? decoded['documentVersion'] : null;
        if (version is String && isValidLegalVersion(version)) {
          _acceptedVersion = version;
        }
      }
    } catch (e) {
      debugPrint('terms: read cache failed: $e');
    }

    _applyLocalVerdict();
  }

  /// Decides from the device record alone, against the freshest known policy.
  void _applyLocalVerdict() {
    final policy = _policy();
    _appliedPolicy = policy;
    if (isRemote && _acceptedVersion == null) return;
    var verdict = legalVerdict(_acceptedVersion, policy, DateTime.now());
    if (isRemote && verdict == TermsGateStatus.required) {
      verdict = TermsGateStatus.requested;
    }
    _setStatus(verdict);
  }

  /// The device-known policy moved (a `/v1/config` refresh landed). Local
  /// accounts re-decide right here — that is what makes a backend policy
  /// change show up in this launch instead of the next one. Remote accounts
  /// re-ask the backend instead of re-deciding: the config copy of the policy
  /// can be older than the verdict already in hand, and only the server may
  /// hard block them.
  void _onPolicyChanged() {
    final policy = _policy();
    if (policy == _appliedPolicy) return;
    if (!isRemote) {
      _applyLocalVerdict();
      return;
    }
    _appliedPolicy = policy;
    if (_checking) {
      // A verdict for the previous policy is in flight; re-ask once it lands.
      _recheckQueued = true;
    } else if (_serverChecked) {
      _serverChecked = false;
      // Rebuilds `_TermsGate`, which calls `checkRemote` when authenticated.
      _notify();
    }
    // Otherwise the first check hasn't run yet and will answer for the new
    // policy anyway — the server evaluates it, not us.
  }

  /// Asks the backend for the authoritative verdict. Call once Convex auth is
  /// attached. Network failure keeps whatever [load] concluded — the app
  /// stays usable and the next launch retries.
  ///
  /// Runs even when the device record already says the current documents were
  /// accepted: that record was matched against the policy this device happens
  /// to know, so skipping the call would hide a policy published since — the
  /// gate would need a second launch to appear.
  Future<void> checkRemote() async {
    if (!isRemote || _serverChecked) return;
    _serverChecked = true;
    _checking = true;
    try {
      final raw = await _resolvedClient.query(
        'v1/legal/queries:getMyAcceptance',
        {},
      );
      final decoded = decodeConvexResponse(raw);
      if (decoded is! Map) return;

      final current = decoded['currentVersion'];
      if (current is String && isValidLegalVersion(current)) {
        _serverCurrentVersion = current;
        final grace = decoded['graceEndsAt'];
        _serverGraceEndsAt = grace is num ? grace.round() : null;
        _serverPolicyKnown = true;
      }

      // Cache the server-known acceptance so offline launches can evaluate.
      final accepted = decoded['acceptedVersion'];
      if (accepted is String && isValidLegalVersion(accepted)) {
        _acceptedVersion = accepted;
        final acceptedAt = decoded['acceptedAt'];
        await writeTermsAcceptanceRecord(
          _storage,
          accountId: accountId,
          documentVersion: accepted,
          acceptedAt: acceptedAt is num ? acceptedAt.round() : null,
        );
      }

      final status = decoded['status'];
      _setStatus(switch (status) {
        'ok' => TermsGateStatus.cleared,
        'reacceptRequired' => TermsGateStatus.required,
        // Forward compatibility: an unrecognized status degrades to the
        // dismissible prompt, never to a hard block.
        _ => TermsGateStatus.requested,
      });
    } catch (e) {
      debugPrint('terms: acceptance check failed: $e');
    } finally {
      _checking = false;
      if (_recheckQueued) {
        // The policy moved while this call was in flight: the answer just
        // applied is stale, so ask again for the policy now in force.
        _recheckQueued = false;
        _serverChecked = false;
        _notify();
      }
    }
  }

  /// Records the user's affirmative acceptance from the gate screen:
  /// server-side for remote accounts (then cached), device-side for local
  /// ones. Throws on failure so the screen can surface it.
  Future<void> accept() async {
    final version = currentVersion;
    if (isRemote) {
      await _resolvedClient.mutation(
        name: 'v1/legal/mutations:accept',
        args: {'documentVersion': version},
      );
    }
    await writeTermsAcceptanceRecord(
      _storage,
      accountId: accountId,
      documentVersion: version,
    );
    _acceptedVersion = version;
    _setStatus(TermsGateStatus.cleared);
  }

  /// "Not now" on the soft prompt: hides it for the rest of this app launch
  /// (per documents version). Never available while the gate is blocking.
  void dismissPrompt() {
    if (_dismissedVersion == currentVersion) return;
    _dismissedVersion = currentVersion;
    _notify();
  }

  void _setStatus(TermsGateStatus next) {
    if (_status == next) return;
    _status = next;
    _notify();
  }

  /// Switching accounts disposes this controller while a check may still be in
  /// flight; the answer that lands afterwards belongs to a gate that no longer
  /// exists, and notifying a disposed [ChangeNotifier] throws.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _policyChanges?.removeListener(_onPolicyChanged);
    super.dispose();
  }
}
