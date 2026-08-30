import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/components/dashboard/dashboard_view.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
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

  // Edit mode is driven by drag-and-drop, and the tiles used to be
  // `LongPressDraggable`s: with a mouse you had to press and hold half a second
  // on every tile before it would move, which reads as "dragging is broken" on
  // desktop. Mouse pointers now start dragging on movement instead. The three
  // tests below pin the whole trade-off — mouse drags immediately, touch still
  // waits (or the enclosing home `ListView` would stop scrolling), and a click
  // with a little hand jitter is still a click.
  group('drag start', () {
    late String? swapped;
    late String? tapped;

    Future<void> pumpTwoTiles(WidgetTester tester) async {
      swapped = null;
      tapped = null;
      final items = [
        for (final (index, col) in const [0, 2].indexed)
          DashboardViewItem(
            row: _row('stat-$index', index, 'third', 1, col),
            spec: StatWidgetSpec(
              title: 'stat-$index',
              filter: const TransactionFilter(),
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
                    onTapItem: (item) => tapped = item.row.id,
                    onSwap: (draggedId, targetId) => swapped = targetId,
                    onPlaceInCell: (_, _, _, _) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> disposeStreams(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('a mouse drags a tile without holding it down first', (
      tester,
    ) async {
      await pumpTwoTiles(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('stat-0')),
        kind: PointerDeviceKind.mouse,
      );
      // Deliberately no `pump(kLongPressTimeout)`: the drag has to be live off
      // the movement alone, which is the whole point of the change.
      await gesture.moveTo(tester.getCenter(find.text('stat-1')));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(swapped, 'stat-1');

      await disposeStreams(tester);
    });

    testWidgets('touch still waits for the long press before dragging', (
      tester,
    ) async {
      await pumpTwoTiles(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('stat-0')),
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveTo(tester.getCenter(find.text('stat-1')));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // A finger that moves straight away is scrolling the home list, not
      // rearranging the dashboard.
      expect(swapped, isNull);

      await disposeStreams(tester);
    });

    testWidgets('a click carrying a few pixels of jitter still selects', (
      tester,
    ) async {
      await pumpTwoTiles(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('stat-0')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(2, 1));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tapped, 'stat-0');
      expect(swapped, isNull);

      await disposeStreams(tester);
    });
  });

  // Two thirds side by side on the last row can neither slide sideways nor go
  // up, so without a row underneath neither can be moved out of the way and
  // neither can grow. Edit mode therefore always keeps one spare row below the
  // board, and a tile dropped into it lands on the row past the last one.
  group('spare row', () {
    ({int row, int col, DashboardWidth width})? placed;
    ({int row, int col, int maxUnits})? added;

    Future<void> pumpBoard(WidgetTester tester, {required bool editing}) async {
      placed = null;
      added = null;
      final items = [
        for (final (index, col) in const [0, 2].indexed)
          DashboardViewItem(
            row: _row('stat-$index', index, 'third', 0, col),
            spec: StatWidgetSpec(
              title: 'stat-$index',
              filter: const TransactionFilter(),
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
                    editing: editing,
                    onPlaceInCell: (_, row, col, width) =>
                        placed = (row: row, col: col, width: width),
                    onAddWidget: (row, col, maxUnits) =>
                        added = (row: row, col: col, maxUnits: maxUnits),
                    onSwap: (_, _) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> disposeStreams(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('is there while editing and gone in view mode', (tester) async {
      await pumpBoard(tester, editing: true);
      final editingHeight = tester.getSize(find.byType(DashboardView)).height;
      expect(tester.takeException(), isNull);
      await disposeStreams(tester);

      await pumpBoard(tester, editing: false);
      final viewHeight = tester.getSize(find.byType(DashboardView)).height;
      expect(tester.takeException(), isNull);

      // Exactly one spare row taller, gap included.
      expect(editingHeight - viewHeight, 88.0 + 4.0);

      await disposeStreams(tester);
    });

    testWidgets('accepts a tile dropped past the last row', (tester) async {
      await pumpBoard(tester, editing: true);

      // The spare row's own band: below the single real row of tiles.
      final board = tester.getRect(find.byType(DashboardView));
      final target = Offset(board.left + 40, board.bottom - 40);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('stat-1')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(placed, isNotNull);
      expect(placed!.row, 1, reason: 'the row past the last real one');
      expect(placed!.col, 0);

      await disposeStreams(tester);
    });

    testWidgets('its + adds a widget on the row past the last', (tester) async {
      await pumpBoard(tester, editing: true);

      final board = tester.getRect(find.byType(DashboardView));
      await tester.tapAt(Offset(board.center.dx, board.bottom - 40));
      await tester.pumpAndSettle();

      expect(added, isNotNull);
      expect(added!.row, 1);
      expect(added!.col, 0);
      expect(added!.maxUnits, dashboardGridUnits);

      await disposeStreams(tester);
    });
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
