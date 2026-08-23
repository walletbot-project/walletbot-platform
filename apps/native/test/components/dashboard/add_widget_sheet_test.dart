import 'dart:convert';

import 'package:app/components/dashboard/add_widget_sheet.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
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

  /// The sheet scrolls, and it is taller than the 800x600 test viewport, so a
  /// control near the bottom has to be brought into view before it can be hit.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await settle(tester);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> tapChip(WidgetTester tester, String label) =>
      tapVisible(tester, find.text(label));

  /// Taps the sheet's confirm button — `Add` when creating, `Save` when
  /// editing — and lets the write settle.
  Future<void> submit(WidgetTester tester, {required bool editing}) =>
      tapVisible(tester, find.text(editing ? 'Save' : 'Add'));

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

  /// The single stored widget row, decoded.
  Future<Map<String, Object?>> storedOptions() async {
    final rows = await repos.dashboard.listActive();
    return jsonDecode(rows.single.options) as Map<String, Object?>;
  }

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

    testWidgets('the picked width is stored, not just the type default', (
      tester,
    ) async {
      await openSheet(tester, (context) => showAddWidgetSheet(context, repos));
      await tapChip(tester, 'Balance');
      await typeTitle(tester, 'Total');
      // The balance card defaults to `half` (1/2); pick the full width chip.
      await tapChip(tester, '1/1');
      await submit(tester, editing: false);

      final rows = await repos.dashboard.listActive();
      expect(rows.single.width, 'full');
    });

    testWidgets('a width too wide for the target cell is not offered', (
      tester,
    ) async {
      await openSheet(
        tester,
        (context) => showAddWidgetSheet(
          context,
          repos,
          at: const DashboardLayoutCoord(row: 0, col: 4),
          maxUnits: 2,
        ),
      );
      // 2 units is exactly a `1/3`; everything wider must be off the picker.
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('1/2'), findsNothing);
      expect(find.text('2/3'), findsNothing);
      expect(find.text('1/1'), findsNothing);
    });
  });

  group('balance card scope', () {
    testWidgets('with no account chosen it stores an empty scope', (
      tester,
    ) async {
      await repos.accounts.create(name: 'Efectivo', currency: 'ARS');

      await openSheet(tester, (context) => showAddWidgetSheet(context, repos));
      await tapChip(tester, 'Balance');
      await typeTitle(tester, 'Total');
      await submit(tester, editing: false);

      final options = await storedOptions();
      expect(options['currency'], 'ARS');
      expect(options['accountIds'], isEmpty);
    });

    testWidgets('a chosen account is stored as the scope', (tester) async {
      final cash = await repos.accounts.create(
        name: 'Efectivo',
        currency: 'ARS',
      );
      await repos.accounts.create(name: 'Banco', currency: 'ARS');

      await openSheet(tester, (context) => showAddWidgetSheet(context, repos));
      await tapChip(tester, 'Balance');
      await typeTitle(tester, 'Solo caja');
      await tapVisible(tester, find.widgetWithText(FilterChip, 'Efectivo'));
      await submit(tester, editing: false);

      expect((await storedOptions())['accountIds'], [cash]);
    });

    testWidgets('only accounts of the chosen currency are offered', (
      tester,
    ) async {
      await repos.accounts.create(name: 'Efectivo', currency: 'ARS');
      await repos.accounts.create(name: 'Dolares', currency: 'USD');

      await openSheet(tester, (context) => showAddWidgetSheet(context, repos));
      await tapChip(tester, 'Balance');
      // ARS sorts first, so it is the currency the sheet lands on.
      expect(find.widgetWithText(FilterChip, 'Efectivo'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Dolares'), findsNothing);

      await tapChip(tester, 'USD');
      expect(find.widgetWithText(FilterChip, 'Efectivo'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'Dolares'), findsOneWidget);
    });

    testWidgets('an edit that does not touch the scope keeps it', (
      tester,
    ) async {
      final cash = await repos.accounts.create(
        name: 'Efectivo',
        currency: 'ARS',
      );
      await repos.dashboard.create(
        type: 'balance',
        position: 0,
        width: 'half',
        options: jsonEncode({
          'title': 'Efectivo',
          'currency': 'ARS',
          'accountIds': [cash],
          'layout': {'row': 0, 'col': 0},
        }),
      );
      final stored = (await repos.dashboard.listActive()).single;

      await openSheet(
        tester,
        (context) => showEditWidgetSheet(
          context,
          repos,
          stored,
          const TransactionFilter(),
        ),
      );
      await typeTitle(tester, 'Caja');
      await submit(tester, editing: true);

      final options = await storedOptions();
      expect(options['title'], 'Caja');
      expect(options['accountIds'], [cash]);
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
