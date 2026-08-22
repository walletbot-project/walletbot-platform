import 'package:app/components/dashboard/add_widget_sheet.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The confirm button's enabled state, which is what `_canSubmit` drives.
///
/// A widget of a transaction-reading type must carry a filter before it can be
/// created — the rule reviewed on PR #229 — while a tile already *stored*
/// without one (the default seed's `seed-wgt-recientes`) stays editable.
void main() {
  late AppDatabase db;
  late AppRepositories repos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
  });

  tearDown(() => db.close());

  /// `pumpAndSettle` would never return: the unconfigured filter
  /// call-to-action pulses forever by design. Pump a fixed budget instead —
  /// enough for the modal route transition and the async currency load.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Pumps a host whose single button opens the sheet.
  Future<void> openSheet(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  /// The sheet's confirm button — `Add` when creating, `Save` when editing.
  bool confirmEnabled(WidgetTester tester, {required bool editing}) {
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(editing ? 'Save' : 'Add'),
        matching: find.byType(FilledButton),
      ),
    );
    return button.onPressed != null;
  }

  Future<void> typeTitle(WidgetTester tester, String title) async {
    await tester.enterText(
      find.ancestor(of: find.text('Title'), matching: find.byType(TextField)),
      title,
    );
    await settle(tester);
  }

  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await settle(tester);
  }

  DashboardWidget storedWidget({required String type, String? filterId}) =>
      DashboardWidget(
        id: 'wgt-1',
        type: type,
        filterId: filterId,
        position: 0,
        width: 'third',
        options: '{"title":"Stored","layout":{"row":0,"col":0}}',
        archived: false,
        createdAt: BigInt.one,
        updatedAt: BigInt.one,
        dirty: false,
      );

  const someFilter = TransactionFilter(types: {TxnType.expense});

  group('creating', () {
    testWidgets('a stat with no title and no filter cannot be added', (
      tester,
    ) async {
      await openSheet(tester, (context) => showAddWidgetSheet(context, repos));
      expect(confirmEnabled(tester, editing: false), isFalse);
    });

    testWidgets('a titled stat still cannot be added without a filter', (
      tester,
    ) async {
      await openSheet(tester, (context) => showAddWidgetSheet(context, repos));
      await typeTitle(tester, 'Groceries');
      expect(confirmEnabled(tester, editing: false), isFalse);
    });

    testWidgets('a balance card needs no filter', (tester) async {
      await openSheet(tester, (context) => showAddWidgetSheet(context, repos));
      await tapChip(tester, 'Balance');
      await typeTitle(tester, 'Total');
      expect(confirmEnabled(tester, editing: false), isTrue);
    });
  });

  group('editing', () {
    testWidgets('a tile stored without a filter stays saveable', (
      tester,
    ) async {
      await openSheet(
        tester,
        (context) => showEditWidgetSheet(
          context,
          repos,
          storedWidget(type: 'list'),
          const TransactionFilter(),
        ),
      );
      expect(confirmEnabled(tester, editing: true), isTrue);
    });

    testWidgets('a filtered tile whose filter is cleared cannot be saved', (
      tester,
    ) async {
      await openSheet(
        tester,
        (context) => showEditWidgetSheet(
          context,
          repos,
          storedWidget(type: 'stat', filterId: 'flt-1'),
          someFilter,
        ),
      );
      expect(confirmEnabled(tester, editing: true), isTrue);

      // The call-to-action's ✕ empties the filter, which is the one way an
      // already-filtered tile can lose its filter inside this sheet.
      await tester.tap(find.byIcon(Icons.close));
      await settle(tester);
      expect(confirmEnabled(tester, editing: true), isFalse);
    });

    testWidgets('a balance card turned into a stat needs a filter', (
      tester,
    ) async {
      await openSheet(
        tester,
        (context) => showEditWidgetSheet(
          context,
          repos,
          storedWidget(type: 'balance'),
          const TransactionFilter(),
        ),
      );
      expect(confirmEnabled(tester, editing: true), isTrue);

      await tapChip(tester, 'Value');
      expect(confirmEnabled(tester, editing: true), isFalse);
    });
  });
}
