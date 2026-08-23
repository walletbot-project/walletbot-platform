import 'package:app/app_config/client_info.dart';
import 'package:app/database.dart';
import 'package:app/legal/legal_acceptance_controller.dart';
import 'package:app/legal/legal_versions.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _clientInfo = ClientInfo(
  platform: 'android',
  appVersion: '1.2.3',
  deviceId: 'test-device',
);

LegalVersions _versions({
  String termsCurrent = '2026-08-06',
  String termsMin = '2026-08-06',
  String privacyCurrent = '2026-08-06',
  String privacyMin = '2026-08-06',
}) => LegalVersions(
  terms: LegalDocumentVersions(current: termsCurrent, min: termsMin),
  privacy: LegalDocumentVersions(current: privacyCurrent, min: privacyMin),
);

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  LegalAcceptanceController controller({LegalVersions? versions}) =>
      LegalAcceptanceController(
        db: db,
        accountId: 'local_1',
        isRemote: false,
        clientInfo: _clientInfo,
        locale: 'es-AR',
        versions: versions ?? _versions(),
      );

  Future<void> seedAcceptance(
    LegalDocumentKind document,
    String version,
  ) async {
    await db.into(db.legalAcceptances).insert(
      LegalAcceptancesCompanion.insert(
        id: 'seed-${document.name}-$version',
        document: document,
        version: version,
        acceptedAt: BigInt.from(1000),
        ageConfirmed: const Value(true),
        platform: 'android',
        source: LegalAcceptanceSource.local,
      ),
    );
  }

  group('remote accounts', () {
    // The shape of `v1/legal/queries:acceptanceStatus`.
    Map<Object?, Object?> statusResponse({
      String? acceptedTerms,
      String? acceptedPrivacy,
      String current = '2026-08-06',
      String min = '2026-08-06',
    }) => {
      'terms': {
        'accepted': acceptedTerms,
        'acceptedAt': acceptedTerms == null ? null : 1000,
        'current': current,
        'min': min,
      },
      'privacy': {
        'accepted': acceptedPrivacy,
        'acceptedAt': acceptedPrivacy == null ? null : 1000,
        'current': current,
        'min': min,
      },
    };

    LegalAcceptanceController remoteController(
      LegalAcceptanceStatusFetcher fetch,
    ) => LegalAcceptanceController(
      db: db,
      accountId: 'user_1',
      isRemote: true,
      clientInfo: _clientInfo,
      locale: 'es-AR',
      versions: _versions(),
      fetchStatus: fetch,
    );

    // The bug this file exists to prevent: the status query used to be fired
    // the frame after sign-in, before `setAuthWithRefresh` had authenticated
    // the socket. It came back `Unauthenticated`, the controller treated that
    // as "nothing owed", and the gate silently never appeared.
    test('an unauthenticated first attempt is retried, not taken as a verdict', () async {
      var attempts = 0;
      final legal = remoteController(() async {
        attempts += 1;
        if (attempts == 1) throw StateError('Unauthenticated');
        return statusResponse();
      });
      addTearDown(legal.dispose);

      await legal.load();
      // Nothing local to go on: still waiting on the backend.
      expect(legal.resolved, isFalse);
      expect(legal.remoteRefreshPending, isTrue);

      await legal.refreshRemote();
      // Failed, so it fails OPEN — but the verdict is still owed.
      expect(legal.resolved, isTrue);
      expect(legal.shouldShowGate, isFalse);
      expect(legal.remoteRefreshPending, isTrue);

      await legal.refreshRemote();
      expect(attempts, 2);
      expect(legal.remoteRefreshPending, isFalse);
      expect(legal.verdict.pending, LegalDocumentKind.values);
      expect(legal.verdict.blocking, isTrue);
      expect(legal.shouldShowGate, isTrue);
    });

    test('an unreachable backend never gates an offline user', () async {
      final legal = remoteController(
        () async => throw StateError('offline'),
      );
      addTearDown(legal.dispose);

      await legal.load();
      await legal.refreshRemote();

      expect(legal.resolved, isTrue);
      expect(legal.shouldShowGate, isFalse);
      expect(legal.verdict.pending, isEmpty);
    });

    test('the backend answer is mirrored locally with its own timestamp', () async {
      final legal = remoteController(
        () async => statusResponse(
          acceptedTerms: '2026-08-06',
          acceptedPrivacy: '2026-08-06',
        ),
      );
      addTearDown(legal.dispose);

      await legal.load();
      await legal.refreshRemote();

      expect(legal.shouldShowGate, isFalse);
      final rows = await db.select(db.legalAcceptances).get();
      expect(rows, hasLength(2));
      expect(
        rows.every((row) => row.source == LegalAcceptanceSource.remote),
        isTrue,
      );
      // The server's timestamp, never a fabricated `now`.
      expect(rows.every((row) => row.acceptedAt == BigInt.from(1000)), isTrue);

      // Mirrored, so a second call cannot duplicate the rows.
      await legal.refreshRemote();
      expect(await db.select(db.legalAcceptances).get(), hasLength(2));
    });

    test('the server versions win over a stale cached config', () async {
      final legal = remoteController(
        () async => statusResponse(
          acceptedTerms: '2026-08-06',
          acceptedPrivacy: '2026-08-06',
          // The backend has moved on; the controller was built with the older
          // bundled/cached pair.
          current: '2026-09-01',
          min: '2026-08-06',
        ),
      );
      addTearDown(legal.dispose);

      await legal.load();
      await legal.refreshRemote();

      expect(legal.versions.terms.current, '2026-09-01');
      expect(legal.verdict.pending, LegalDocumentKind.values);
      // Inside the grace period, so it can wait.
      expect(legal.verdict.blocking, isFalse);
      expect(legal.shouldShowGate, isTrue);
    });

    test('a local mirror answers before the backend does', () async {
      await db.into(db.legalAcceptances).insert(
        LegalAcceptancesCompanion.insert(
          id: 'remote:terms:2026-08-06',
          document: LegalDocumentKind.terms,
          version: '2026-08-06',
          acceptedAt: BigInt.from(1000),
          ageConfirmed: const Value(true),
          platform: 'server',
          source: LegalAcceptanceSource.remote,
        ),
      );
      await db.into(db.legalAcceptances).insert(
        LegalAcceptancesCompanion.insert(
          id: 'remote:privacy:2026-08-06',
          document: LegalDocumentKind.privacy,
          version: '2026-08-06',
          acceptedAt: BigInt.from(1000),
          ageConfirmed: const Value(true),
          platform: 'server',
          source: LegalAcceptanceSource.remote,
        ),
      );

      final legal = remoteController(
        () async => throw StateError('offline'),
      );
      addTearDown(legal.dispose);

      await legal.load();
      // Resolved from the mirror without any network at all.
      expect(legal.resolved, isTrue);
      expect(legal.shouldShowGate, isFalse);
      // And still owed, so a later launch re-checks.
      expect(legal.remoteRefreshPending, isTrue);
    });
  });

  test('a fresh local account is blocked until it accepts', () async {
    final legal = controller();
    addTearDown(legal.dispose);

    await legal.load();

    expect(legal.resolved, isTrue);
    expect(legal.verdict.pending, LegalDocumentKind.values);
    expect(legal.verdict.blocking, isTrue);
    expect(legal.verdict.firstAcceptance, isTrue);
    expect(legal.shouldShowGate, isTrue);
    // Blocking has no "later".
    legal.dismissForSession();
    expect(legal.shouldShowGate, isTrue);

    await legal.accept(
      documents: LegalDocumentKind.values,
      ageConfirmed: true,
    );

    expect(legal.shouldShowGate, isFalse);
    final rows = await db.select(db.legalAcceptances).get();
    expect(rows, hasLength(2));
    expect(rows.every((row) => row.ageConfirmed), isTrue);
    expect(rows.every((row) => row.version == '2026-08-06'), isTrue);
    expect(
      rows.every((row) => row.source == LegalAcceptanceSource.local),
      isTrue,
    );
    expect(rows.every((row) => row.platform == 'android'), isTrue);
    expect(rows.every((row) => row.appVersion == '1.2.3'), isTrue);
  });

  test('accepting is refused without the age confirmation', () async {
    final legal = controller();
    addTearDown(legal.dispose);
    await legal.load();

    await expectLater(
      legal.accept(documents: LegalDocumentKind.values, ageConfirmed: false),
      throwsArgumentError,
    );
    expect(await db.select(db.legalAcceptances).get(), isEmpty);
  });

  test('only the document that changed is asked for', () async {
    await seedAcceptance(LegalDocumentKind.terms, '2026-08-06');
    await seedAcceptance(LegalDocumentKind.privacy, '2026-08-06');

    final legal = controller(
      versions: _versions(privacyCurrent: '2026-09-01'),
    );
    addTearDown(legal.dispose);
    await legal.load();

    expect(legal.verdict.pending, [LegalDocumentKind.privacy]);
    expect(legal.verdict.firstAcceptance, isFalse);
    // The floor is still the accepted version: inside the grace period.
    expect(legal.verdict.blocking, isFalse);
  });

  test('inside the grace period the prompt can wait', () async {
    await seedAcceptance(LegalDocumentKind.terms, '2026-08-06');
    await seedAcceptance(LegalDocumentKind.privacy, '2026-08-06');

    final legal = controller(
      versions: _versions(
        termsCurrent: '2026-09-01',
        privacyCurrent: '2026-09-01',
      ),
    );
    addTearDown(legal.dispose);
    await legal.load();

    expect(legal.verdict.blocking, isFalse);
    expect(legal.shouldShowGate, isTrue);

    legal.dismissForSession();
    expect(legal.shouldShowGate, isFalse);
    // Dismissed, not accepted: nothing was recorded.
    expect(await db.select(db.legalAcceptances).get(), hasLength(2));
  });

  test('raising the floor past the accepted version blocks', () async {
    await seedAcceptance(LegalDocumentKind.terms, '2026-08-06');
    await seedAcceptance(LegalDocumentKind.privacy, '2026-08-06');

    final legal = controller(
      versions: _versions(termsCurrent: '2026-09-01', termsMin: '2026-09-01'),
    );
    addTearDown(legal.dispose);
    await legal.load();

    expect(legal.verdict.pending, [LegalDocumentKind.terms]);
    expect(legal.verdict.blocking, isTrue);
    legal.dismissForSession();
    expect(legal.shouldShowGate, isTrue);
  });

  test('the highest accepted version wins over an older row', () async {
    await seedAcceptance(LegalDocumentKind.terms, '2026-09-01');
    await seedAcceptance(LegalDocumentKind.terms, '2026-08-06');
    await seedAcceptance(LegalDocumentKind.privacy, '2026-09-01');

    final legal = controller(
      versions: _versions(
        termsCurrent: '2026-09-01',
        privacyCurrent: '2026-09-01',
      ),
    );
    addTearDown(legal.dispose);
    await legal.load();

    expect(legal.verdict.pending, isEmpty);
    expect(legal.shouldShowGate, isFalse);
  });
}
