import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/voice_action_widget.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late AppDatabase db;
  late AppRepositories repos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('preview coverage includes every editable entity write', () {
    expect(previewableToolNames, {
      'addExpense',
      'addIncome',
      'addTransfer',
      'addBalanceAdjustment',
      'createAccount',
      'updateAccount',
      'createCategory',
      'updateCategory',
      'createTag',
      'updateTag',
      'updateTransaction',
    });
  });

  testWidgets('update account renders an editor with a safe save action', (
    tester,
  ) async {
    final accountId = await repos.accounts.create(
      name: 'Efectivo',
      currency: 'ARS',
      description: 'Billetera diaria',
    );

    await tester.pumpWidget(
      Provider<AppRepositories>.value(
        value: repos,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VoiceActionWidget(
              toolName: 'updateAccount',
              entityId: accountId,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Efectivo'), findsOneWidget);
    expect(find.text('Cuenta actualizada'), findsOneWidget);

    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();

    expect(find.text('Editar cuenta'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Guardar'), findsOneWidget);

    final safeAreas = tester
        .widgetList<SafeArea>(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(SafeArea),
          ),
        )
        .toList();
    expect(
      safeAreas.any((safeArea) => safeArea.maintainBottomViewPadding),
      isTrue,
    );
  });
}
