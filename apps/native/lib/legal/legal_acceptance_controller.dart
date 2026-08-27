import 'dart:async';

import 'package:app/app_config/app_config_controller.dart';
import 'package:app/app_config/client_info.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/data/ids.dart';
import 'package:app/database.dart';
import 'package:app/legal/legal_versions.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

/// Fetches `v1/legal/queries:acceptanceStatus`, already decoded.
///
/// Injectable so tests can drive the remote path — and its failure modes —
/// without a live `ConvexClient`.
typedef LegalAcceptanceStatusFetcher = Future<Map<Object?, Object?>> Function();

/// What the acceptance gate should do for the active account.
@immutable
class LegalGateVerdict {
  const LegalGateVerdict({
    required this.pending,
    required this.blocking,
    required this.firstAcceptance,
    required this.versions,
  });

  /// Documents that still need acceptance, in a stable order. Empty means the
  /// gate stays closed.
  final List<LegalDocumentKind> pending;

  /// Nothing was accepted at or above the floor: the only ways out are
  /// accepting, or leaving the account.
  final bool blocking;

  /// Nothing was ever accepted — a first acceptance, not an update.
  final bool firstAcceptance;

  final LegalVersions versions;

  bool get isEmpty => pending.isEmpty;
}

/// Owns the Terms/Privacy acceptance state of one account.
///
/// Same shape as [AppConfigController] and `DefaultCurrencyController`: local
/// data answers first, the network refines, and **every failure fails open** —
/// a user is never locked out of their own offline data by a gate we could not
/// evaluate (CLAUDE.md: native config fails open).
///
/// Two account kinds, one controller:
/// - **local-only**: the drift table is the whole truth. Its first run has no
///   rows, so the gate asks, and the acceptance is recorded on the device.
/// - **remote**: the backend is authoritative
///   (`v1/legal/queries:acceptanceStatus`). Rows are mirrored into drift so a
///   later offline launch resolves instantly instead of flashing the gate, and
///   an EMPTY mirror never triggers the gate on its own — an empty mirror means
///   "this device has not learned anything yet", not "nothing was accepted".
///
/// Scoped per account, like `AppDatabase` and `DefaultCurrencyController`:
/// callers must create a fresh instance per account.
class LegalAcceptanceController extends ChangeNotifier {
  LegalAcceptanceController({
    required AppDatabase db,
    required this.accountId,
    required this.isRemote,
    required ClientInfo clientInfo,
    required String locale,
    AppConfigController? appConfig,
    LegalVersions? versions,
    ConvexClient? client,
    LegalAcceptanceStatusFetcher? fetchStatus,
  }) : _db = db,
       _clientInfo = clientInfo,
       _locale = locale,
       _appConfig = appConfig,
       _versions =
           versions ?? appConfig?.legalVersions ?? LegalVersions.bundled,
       _client = client,
       _fetchStatus = fetchStatus {
    _appConfig?.addListener(_onConfigChanged);
  }

  final AppDatabase _db;
  final String accountId;
  final bool isRemote;
  final ClientInfo _clientInfo;
  final String _locale;
  final AppConfigController? _appConfig;
  // Only ever touched when `isRemote` is true, so local accounts and widget
  // tests can run without a Convex transport.
  final ConvexClient? _client;
  ConvexClient get _resolvedClient {
    final client = _client;
    if (client == null) throw StateError('legal: no ConvexClient');
    return client;
  }

  final LegalAcceptanceStatusFetcher? _fetchStatus;

  /// How long the gate may hold the app back waiting for a first remote
  /// answer. Past this it fails open — never a spinner the user cannot pass.
  static const Duration _failOpenAfter = Duration(seconds: 6);

  Timer? _failOpenTimer;
  bool _refreshInFlight = false;

  LegalVersions _versions;

  /// Highest accepted version per document, from whichever source is currently
  /// authoritative. Absent key = nothing known.
  Map<LegalDocumentKind, String> _accepted = const {};

  bool _hasLocalRows = false;
  bool _resolved = false;

  /// The backend has answered at least once for this account. While false and
  /// [isRemote], its verdict is still owed — see [remoteRefreshPending].
  bool _remoteAnswered = false;

  /// The remote status could not be resolved and there is no local evidence,
  /// so we know nothing and must not gate.
  bool _remoteUnknown = false;

  /// Session-scoped "Later". Only reachable while the grace period runs, so at
  /// worst the user is nudged again next launch — which is the point of a nudge.
  bool _dismissed = false;

  LegalVersions get versions => _versions;

  /// False until the first resolution attempt finished. The gate shows nothing
  /// while unknown rather than flashing the app or the gate.
  bool get resolved => _resolved;

  /// A remote account whose backend verdict is still owed, because the query
  /// has not succeeded yet. The caller retries [refreshRemote] when Convex
  /// auth reports itself authenticated; until then a `requireAuth` failure is
  /// the expected answer, not a verdict.
  bool get remoteRefreshPending => isRemote && !_remoteAnswered;

  LegalGateVerdict get verdict {
    if (!_resolved || _remoteUnknown) {
      return LegalGateVerdict(
        pending: const [],
        blocking: false,
        firstAcceptance: false,
        versions: _versions,
      );
    }

    final pending = <LegalDocumentKind>[];
    var blocking = false;
    var everAccepted = false;
    for (final document in LegalDocumentKind.values) {
      final accepted = _accepted[document];
      if (accepted != null) everAccepted = true;
      final status = legalDocumentAcceptanceStatus(
        versions: _versions.of(document),
        accepted: accepted,
      );
      if (status == LegalDocumentAcceptanceStatus.current) continue;
      pending.add(document);
      if (status == LegalDocumentAcceptanceStatus.missing) blocking = true;
    }

    return LegalGateVerdict(
      pending: pending,
      blocking: blocking,
      firstAcceptance: !everAccepted,
      versions: _versions,
    );
  }

  /// Whether the gate should replace the app right now.
  bool get shouldShowGate {
    final current = verdict;
    if (current.isEmpty) return false;
    return current.blocking || !_dismissed;
  }

  /// Restores the local rows. Never throws: startup and offline use must not
  /// break on this.
  ///
  /// Deliberately does NOT hit the backend. A remote account's status needs an
  /// authenticated Convex connection, and at the moment this runs — the frame
  /// after sign-in — `ConvexClient.setAuth` has usually not authenticated the
  /// socket yet, so the query comes back `Unauthenticated`. Firing it here and
  /// treating the failure as final is exactly how the gate silently never
  /// appeared: the caller drives [refreshRemote] off
  /// `AuthController.convexAuthenticated` instead.
  Future<void> load() async {
    await _loadLocalRows();
    if (!isRemote) {
      _resolved = true;
      notifyListeners();
      return;
    }
    // Decide from the mirror straight away when there is one, so a returning
    // user does not stare at a spinner (or a flash of the gate) on every
    // launch. A later refresh can still correct it.
    if (_hasLocalRows) {
      _resolved = true;
      notifyListeners();
      return;
    }
    // Nothing local to go on, so the answer has to come from the backend.
    // Bounded: if auth or the network never arrives, fail open rather than
    // leave the user watching a spinner they cannot get past.
    _failOpenTimer?.cancel();
    _failOpenTimer = Timer(_failOpenAfter, () {
      if (_resolved) return;
      debugPrint('legal: no remote status in time, failing open');
      _remoteUnknown = true;
      _resolved = true;
      notifyListeners();
    });
  }

  /// Records the user's acceptance of [documents].
  ///
  /// For a remote account the backend write happens FIRST and a failure
  /// propagates: the gate must not let the user through on an acceptance the
  /// server never recorded, or the next launch would ask again with no
  /// explanation. The local row is written afterwards, as the offline mirror.
  Future<void> accept({
    required List<LegalDocumentKind> documents,
    required bool ageConfirmed,
  }) async {
    if (documents.isEmpty) {
      throw ArgumentError.value(documents, 'documents', 'nothing to accept');
    }
    if (!ageConfirmed) {
      throw ArgumentError.value(
        ageConfirmed,
        'ageConfirmed',
        'age confirmation is required to accept',
      );
    }

    if (isRemote) {
      await _resolvedClient.mutation<Object?>('v1/legal/mutations:accept', {
        'documents': documents.map((d) => d.name).toList(),
        'ageConfirmed': true,
        'platform': _clientInfo.platform,
        'appVersion': _clientInfo.appVersion,
        'locale': _locale,
      });
    }

    final acceptedAt = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    for (final document in documents) {
      final version = _versions.of(document).current;
      await _db
          .into(_db.legalAcceptances)
          .insert(
            LegalAcceptancesCompanion.insert(
              id: newUuid(),
              document: document,
              version: version,
              acceptedAt: acceptedAt,
              ageConfirmed: const Value(true),
              platform: _clientInfo.platform,
              appVersion: Value(_clientInfo.appVersion),
              locale: Value(_locale),
              source: LegalAcceptanceSource.local,
            ),
          );
      _accepted = {..._accepted, document: version};
    }
    _hasLocalRows = true;
    _resolved = true;
    _remoteUnknown = false;
    notifyListeners();

    // The server stamps its own `current`, which can be newer than this
    // build's. Re-read so the mirror reflects what was actually recorded.
    if (isRemote) await refreshRemote();
  }

  /// Dismisses the prompt for this session. Refuses while blocking — that
  /// screen has no "later".
  void dismissForSession() {
    if (verdict.blocking) return;
    if (_dismissed) return;
    _dismissed = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _failOpenTimer?.cancel();
    _appConfig?.removeListener(_onConfigChanged);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _onConfigChanged() {
    final next = _appConfig?.legalVersions;
    if (next == null || next == _versions) return;
    _versions = next;
    // A newer floor can turn an accepted document into a pending one, so the
    // dismissal of the previous prompt no longer applies.
    _dismissed = false;
    notifyListeners();
  }

  Future<void> _loadLocalRows() async {
    try {
      final rows = await _db.select(_db.legalAcceptances).get();
      _hasLocalRows = rows.isNotEmpty;
      final highest = <LegalDocumentKind, String>{};
      for (final row in rows) {
        final previous = highest[row.document];
        if (previous == null || isLegalVersionAtLeast(row.version, previous)) {
          highest[row.document] = row.version;
        }
      }
      _accepted = highest;
    } catch (e) {
      // A read failure must not gate the user.
      debugPrint('legal: reading local acceptances failed: $e');
      _hasLocalRows = false;
      _accepted = const {};
    }
  }

  /// Fetches the backend's verdict for a remote account.
  ///
  /// Safe to call again: a failure leaves [remoteRefreshPending] true so the
  /// next opportunity (auth authenticating, a fresh launch) retries. The first
  /// failure still fails open when there is no local mirror to fall back on —
  /// an unreachable backend must never lock a user out of their own data.
  Future<void> refreshRemote() async {
    if (!isRemote || _refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final decoded = await _resolveStatus().timeout(
        const Duration(seconds: 5),
      );

      final accepted = <LegalDocumentKind, String>{};
      final serverVersions = <LegalDocumentKind, LegalDocumentVersions>{};
      for (final document in LegalDocumentKind.values) {
        final entry = decoded[document.name];
        if (entry is! Map) continue;
        // The response carries the backend's own current/min. Prefer them over
        // the cached config verdict, which can be older than the deploy that
        // published a new document — trusting the cache there would silently
        // skip the prompt.
        final versions = LegalDocumentVersions.fromJson(entry);
        if (versions != null) serverVersions[document] = versions;
        final version = entry['accepted'];
        if (version is! String || version.isEmpty) continue;
        accepted[document] = version;
        await _mirror(
          document: document,
          version: version,
          acceptedAt: entry['acceptedAt'],
        );
      }
      if (serverVersions.length == LegalDocumentKind.values.length) {
        _versions = LegalVersions(
          terms: serverVersions[LegalDocumentKind.terms]!,
          privacy: serverVersions[LegalDocumentKind.privacy]!,
        );
      }
      _accepted = accepted;
      _remoteUnknown = false;
      _remoteAnswered = true;
      _resolved = true;
      _failOpenTimer?.cancel();
      notifyListeners();
    } catch (e) {
      debugPrint('legal: fetching acceptance status failed: $e');
      // NOT an answer: `_remoteAnswered` stays false so the next opportunity
      // retries. But with no local evidence we know nothing right now, so fail
      // open rather than block an offline user out of their own data.
      _remoteUnknown = !_hasLocalRows;
      _resolved = true;
      notifyListeners();
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<Map<Object?, Object?>> _resolveStatus() async {
    final fetch = _fetchStatus;
    if (fetch != null) return fetch();
    final decoded = await _resolvedClient.query<Object?>(
      'v1/legal/queries:acceptanceStatus',
      const {},
    );
    if (decoded is! Map) throw StateError('unexpected response: $decoded');
    return decoded;
  }

  /// Stores the backend's record locally so a later offline launch resolves
  /// without the network. Idempotent through a deterministic id, and it never
  /// invents a timestamp: without one from the server the row is skipped
  /// rather than backdated to now.
  Future<void> _mirror({
    required LegalDocumentKind document,
    required String version,
    required Object? acceptedAt,
  }) async {
    if (acceptedAt is! num) return;
    try {
      await _db
          .into(_db.legalAcceptances)
          .insert(
            LegalAcceptancesCompanion.insert(
              id: 'remote:${document.name}:$version',
              document: document,
              version: version,
              acceptedAt: BigInt.from(acceptedAt.toInt()),
              ageConfirmed: const Value(true),
              platform: 'server',
              source: LegalAcceptanceSource.remote,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      _hasLocalRows = true;
    } catch (e) {
      debugPrint('legal: mirroring acceptance failed: $e');
    }
  }
}
