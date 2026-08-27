import 'package:app/app_config/client_info.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/legal/legal_acceptance_controller.dart';
import 'package:app/legal/legal_versions.dart';
import 'package:app/screens/legal_gate.dart';
import 'package:app/user_settings/default_currency_controller.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<LegalAcceptanceController> pumpGate(
    WidgetTester tester, {
    required LegalVersions versions,
  }) async {
    final controller = LegalAcceptanceController(
      db: db,
      accountId: 'local_1',
      isRemote: false,
      clientInfo: _clientInfo,
      locale: 'es-AR',
      versions: versions,
    );
    addTearDown(controller.dispose);
    await controller.load();

    final auth = AuthController();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<LegalAcceptanceController>.value(
              value: controller,
            ),
            // `.value`, so the provider does not dispose it, same as the
            // other AuthController fixtures in these tests.
            ChangeNotifierProvider<AuthController>.value(value: auth),
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<DefaultCurrencyController>(
              create: (_) => DefaultCurrencyController(
                accountId: 'local_1',
                isRemote: false,
              ),
            ),
          ],
          child: const LegalGateScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> seedAcceptance(
    LegalDocumentKind document,
    String version,
  ) async {
    await db
        .into(db.legalAcceptances)
        .insert(
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

  testWidgets('a first acceptance asks for both documents and blocks', (
    tester,
  ) async {
    await pumpGate(tester, versions: _versions());

    expect(find.text('Antes de empezar'), findsOneWidget);
    expect(
      find.text(
        'Acepto los Términos y Condiciones y la Política de Privacidad',
      ),
      findsOneWidget,
    );
    expect(find.text('Tengo 18 años o más'), findsOneWidget);
    // Blocking: no "later", but never a dead end either.
    expect(find.text('Más tarde'), findsNothing);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('only the updated document is named, and can wait', (
    tester,
  ) async {
    await seedAcceptance(LegalDocumentKind.terms, '2026-08-06');
    await seedAcceptance(LegalDocumentKind.privacy, '2026-08-06');

    await pumpGate(tester, versions: _versions(privacyCurrent: '2026-09-01'));

    expect(find.text('Actualizamos la Política de Privacidad'), findsOneWidget);
    expect(find.text('Acepto la Política de Privacidad'), findsOneWidget);
    // The unchanged document is not re-asked, so it is not named either.
    expect(find.textContaining('Términos y Condiciones'), findsNothing);
    expect(find.text('Más tarde'), findsOneWidget);
  });

  testWidgets('the accept button stays dead until both boxes are ticked', (
    tester,
  ) async {
    final controller = await pumpGate(tester, versions: _versions());

    FilledButton acceptButton() => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Aceptar y continuar'),
        matching: find.byType(FilledButton),
      ),
    );

    expect(acceptButton().onPressed, isNull);

    await tester.tap(find.text('Tengo 18 años o más'));
    await tester.pump();
    expect(acceptButton().onPressed, isNull);

    await tester.tap(
      find.text(
        'Acepto los Términos y Condiciones y la Política de Privacidad',
      ),
    );
    await tester.pump();
    expect(acceptButton().onPressed, isNotNull);

    await tester.tap(find.text('Aceptar y continuar'));
    await tester.pumpAndSettle();

    expect(controller.shouldShowGate, isFalse);
    expect(await db.select(db.legalAcceptances).get(), hasLength(2));
  });

  testWidgets('tapping a document link does not tick the accept box', (
    tester,
  ) async {
    final controller = await pumpGate(tester, versions: _versions());

    // The label is one rich Text; the link is a span inside it, so tap the
    // document name at its own offset rather than the tile's centre.
    final label = find.text(
      'Acepto los Términos y Condiciones y la Política de Privacidad',
    );
    final box = tester.renderObject<RenderBox>(label);
    final topLeft = tester.getTopLeft(label);
    // "Términos y Condiciones" starts a third of the way into the sentence;
    // anywhere inside it is a link hit.
    await tester.tapAt(
      Offset(topLeft.dx + box.size.width * 0.45, topLeft.dy + 8),
    );
    await tester.pumpAndSettle();

    expect(controller.shouldShowGate, isTrue);
    expect(await db.select(db.legalAcceptances).get(), isEmpty);
    // Still dead, because the box was never ticked.
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Aceptar y continuar'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('"later" dismisses the prompt without recording anything', (
    tester,
  ) async {
    await seedAcceptance(LegalDocumentKind.terms, '2026-08-06');
    await seedAcceptance(LegalDocumentKind.privacy, '2026-08-06');

    final controller = await pumpGate(
      tester,
      versions: _versions(
        termsCurrent: '2026-09-01',
        privacyCurrent: '2026-09-01',
      ),
    );

    await tester.tap(find.text('Más tarde'));
    await tester.pumpAndSettle();

    expect(controller.shouldShowGate, isFalse);
    expect(await db.select(db.legalAcceptances).get(), hasLength(2));
  });
}
