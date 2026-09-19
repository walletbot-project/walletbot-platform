import 'package:app/app_config/app_config_controller.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/transaction_form.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _RecurrenceConfig extends AppConfigController {
  @override
  bool isFlagEnabled(String key, {bool orElse = false}) =>
      key == 'recurringExpense';
}

void main() {
  late AppDatabase db;
  late AppRepositories repos;
  late _RecurrenceConfig config;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
    config = _RecurrenceConfig();
    await repos.accounts.create(name: 'Cash', currency: 'ARS');
    await repos.categories.create(name: 'Salary');
  });
  tearDown(() async {
    config.dispose();
    await db.close();
  });

  Future<void> openForm(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var saved = false;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppRepositories>.value(value: repos),
          ChangeNotifierProvider<AppConfigController>.value(value: config),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StatefulBuilder(
            builder: (context, setState) => saved
                ? const Scaffold()
                : TransactionFormScreen(
                    onResult: (_) => setState(() => saved = true),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '100');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Monthly salary',
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
  }

  Future<void> pickDate(WidgetTester tester, String label, String value) async {
    await tester.tap(
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.byType(TextField),
      ),
      value,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Accept'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'monthly form includes the entire final day and preserves an explicit time',
    (tester) async {
      await openForm(tester);
      await pickDate(tester, 'Date', '01/31/2028');
      await pickDate(tester, 'End date (optional)', '05/31/2028');
      await tester.tap(find.byIcon(Icons.schedule_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), '12');
      await tester.enterText(fields.at(1), '00');
      await tester.tap(find.text('PM'));
      await tester.tap(find.widgetWithText(TextButton, 'Accept'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save transaction'));
      await tester.pumpAndSettle();
      final rows = await db.select(db.transactions).get();
      final dates =
          rows
              .map(
                (row) => DateTime.fromMillisecondsSinceEpoch(row.date.toInt()),
              )
              .toList()
            ..sort();
      expect(dates, [
        for (final month in [1, 2, 3, 4, 5]) DateTime(2028, month + 1, 0, 12),
      ]);
      final rule = await db.select(db.recurrences).getSingle();
      expect(
        rule.endDate,
        BigInt.from(
          DateTime(2028, 5, 31, 23, 59, 59, 999).millisecondsSinceEpoch,
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('invalid day intervals cannot save ($brightness)', (
      tester,
    ) async {
      await openForm(tester, brightness: brightness);
      await tester.tap(find.text('Every X days'));
      await tester.pumpAndSettle();
      final interval = find.byKey(const ValueKey('recurrence-day-interval'));
      for (final invalid in ['', '0', '00']) {
        await tester.enterText(interval, invalid);
        await tester.tap(find.text('Save transaction'));
        await tester.pumpAndSettle();
        expect(await db.select(db.transactions).get(), isEmpty);
        expect(
          find.text(invalid.isEmpty ? 'Required' : 'Greater than 0'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.enterText(interval, '2');
      await tester.tap(find.text('Save transaction'));
      await tester.pumpAndSettle();
      expect((await db.select(db.recurrences).getSingle()).dayInterval, 2);
      expect(await db.select(db.transactions).get(), isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
