import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/components/dashboard/dashboard_view.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
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

  tearDown(() => db.close());

  testWidgets('overlapping persisted rows render through the safe reflow', (
    tester,
  ) async {
    final rows = [
      _row('stat-0', 0, 'third', 1, 0),
      _row('stat-1', 1, 'third', 1, 2),
      _row('stat-overlap', 2, 'third', 1, 2),
      _row('stat-2', 3, 'third', 1, 4),
      _row('full-0', 4, 'full', 2, 0),
      _row('full-overlap', 5, 'full', 2, 0),
    ];
    final items = [
      for (final row in rows)
        DashboardViewItem(
          row: row,
          spec: StatWidgetSpec(
            title: row.id,
            filter: const TransactionFilter(),
            aggregation: StatAggregation.count,
            width: DashboardWidth.fromWire(row.width)!,
          ),
        ),
    ];

    await tester.pumpWidget(
      Provider<AppRepositories>.value(
        value: repos,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: 416, child: DashboardView(items: items)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(DashboardView), findsOneWidget);
    expect(find.text('stat-overlap'), findsOneWidget);
    expect(find.text('full-overlap'), findsOneWidget);

    // Explicitly cancel Drift query streams and flush their zero-duration
    // cleanup timer before the widget-test binding verifies pending timers.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  // The floating menu's buttons are icon-only and deliberately carry no
  // `IconButton.tooltip` — a tooltip is an `OverlayPortal`, and the menu is
  // already the overlay child of one, which trips a framework assertion on
  // hover. They are named via `Icon.semanticLabel` instead. This test pins the
  // accessible name to the actual semantics tree, so dropping the label (or
  // "simplifying" it away) fails here rather than silently shipping unlabelled
  // buttons to VoiceOver/TalkBack.
  testWidgets('floating menu icon buttons expose accessible names', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final items = [
      DashboardViewItem(
        row: _row('stat-0', 0, 'third', 1, 0),
        spec: const StatWidgetSpec(
          title: 'stat-0',
          filter: TransactionFilter(),
          aggregation: StatAggregation.count,
          width: DashboardWidth.third,
        ),
      ),
    ];

    await tester.pumpWidget(
      Provider<AppRepositories>.value(
        value: repos,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 416,
                child: DashboardView(
                  items: items,
                  editing: true,
                  selectedItemId: 'stat-0',
                  onWidthChanged: (_, _) {},
                  onNudge: (_, _) {},
                  onEditItem: (_) {},
                  onDeleteItem: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The menu is shown from a post-frame callback, so settle before asserting.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // No tooltip anywhere in the menu: that is the whole point of the change.
    expect(find.byType(Tooltip), findsNothing);

    // Every button must be a *named button* in the semantics tree. Asserting
    // the label alone would still pass if the name drifted onto some inert
    // wrapper, so `isButton` is pinned too. Note this deliberately holds for
    // the disabled move directions as well: a button with nowhere to go is
    // still announced by name, it is just not actionable.
    for (final label in const [
      'Edit',
      'Remove',
      'Move left',
      'Move up',
      'Move down',
      'Move right',
    ]) {
      final finder = find.bySemanticsLabel(label);
      expect(
        finder,
        findsOneWidget,
        reason: '"$label" must stay an accessible name on the floating menu',
      );
      expect(
        tester.getSemantics(finder),
        isSemantics(label: label, isButton: true),
        reason: '"$label" must stay a named button for a11y',
      );
    }

    // Edit and Remove are unconditionally wired here, so they must also be
    // enabled and tappable — proving the name rides on the real button node
    // and not on a decorative sibling.
    for (final label in const ['Edit', 'Remove']) {
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(
          label: label,
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
        reason: '"$label" must stay a tappable, enabled button for a11y',
      );
    }

    // The single tile sits at row 1 / col 0, so only these directions are
    // available. Pinning one enabled and one disabled direction keeps the
    // assertion above honest about what it is and is not proving.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Move right')),
      isSemantics(label: 'Move right', isButton: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Move left')),
      isSemantics(label: 'Move left', isButton: true, hasTapAction: false),
    );

    handle.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

DashboardWidget _row(String id, int position, String width, int row, int col) {
  final now = BigInt.from(position + 1);
  return DashboardWidget(
    id: id,
    type: 'stat',
    position: position,
    width: width,
    options: '{"layout":{"row":$row,"col":$col}}',
    archived: false,
    createdAt: now,
    updatedAt: now,
    dirty: false,
  );
}
