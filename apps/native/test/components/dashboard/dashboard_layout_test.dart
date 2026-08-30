import 'package:app/components/dashboard/dashboard_layout.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolvePlacementSnapshot', () {
    test('keeps a valid stored manual layout', () {
      final result = resolvePlacementSnapshot([
        const PlacementInput(
          id: 'left',
          width: DashboardWidth.third,
          coord: DashboardLayoutCoord(row: 0, col: 0),
        ),
        const PlacementInput(
          id: 'right',
          width: DashboardWidth.twoThirds,
          coord: DashboardLayoutCoord(row: 0, col: 2),
        ),
      ]);

      expect(result.needsRepair, isFalse);
      expect(result.placements, hasLength(2));
      expect(result.placements[1].col, 2);
    });

    test('reflows the exact 140px and 420px overlap regression', () {
      final result = resolvePlacementSnapshot([
        const PlacementInput(
          id: 'stat-0',
          width: DashboardWidth.third,
          coord: DashboardLayoutCoord(row: 1, col: 0),
        ),
        const PlacementInput(
          id: 'stat-1',
          width: DashboardWidth.third,
          coord: DashboardLayoutCoord(row: 1, col: 2),
        ),
        const PlacementInput(
          id: 'stat-overlap',
          width: DashboardWidth.third,
          coord: DashboardLayoutCoord(row: 1, col: 2),
        ),
        const PlacementInput(
          id: 'stat-2',
          width: DashboardWidth.third,
          coord: DashboardLayoutCoord(row: 1, col: 4),
        ),
        const PlacementInput(
          id: 'full-0',
          width: DashboardWidth.full,
          coord: DashboardLayoutCoord(row: 2, col: 0),
        ),
        const PlacementInput(
          id: 'full-overlap',
          width: DashboardWidth.full,
          coord: DashboardLayoutCoord(row: 2, col: 0),
        ),
      ]);

      expect(result.needsRepair, isTrue);
      _expectValidGrid(result.placements);
      expect(result.placements.map((p) => p.id), [
        'stat-0',
        'stat-1',
        'stat-overlap',
        'stat-2',
        'full-0',
        'full-overlap',
      ]);
    });

    test('reflows missing and out-of-bounds coordinates', () {
      final missing = resolvePlacementSnapshot([
        const PlacementInput(
          id: 'missing',
          width: DashboardWidth.third,
          coord: null,
        ),
      ]);
      final outOfBounds = resolvePlacementSnapshot([
        const PlacementInput(
          id: 'outside',
          width: DashboardWidth.third,
          coord: DashboardLayoutCoord(row: 0, col: 6),
        ),
      ]);

      expect(missing.needsRepair, isTrue);
      expect(outOfBounds.needsRepair, isTrue);
      expect(outOfBounds.placements.single.col, 0);
    });

    test('malformed layout JSON is treated as missing', () {
      expect(dashboardLayoutFromOptions('{broken'), isNull);
      expect(
        dashboardLayoutFromOptions('{"layout":{"row":1.5,"col":2}}'),
        isNull,
      );
      expect(
        dashboardLayoutFromOptions('{"layout":{"row":1,"col":-1}}'),
        isNull,
      );
    });

    test('a tile on the bottom row can be nudged onto a fresh row', () {
      // The trap this fixes: two thirds side by side on the last row. Neither
      // can slide sideways and neither can go up, so without a row below,
      // neither can be moved out of the way and neither can grow.
      final layout = DashboardGridLayout.fromPlacements(const [
        WidgetPlacement(
          id: 'left',
          row: 0,
          col: 0,
          width: DashboardWidth.third,
        ),
        WidgetPlacement(
          id: 'right',
          row: 0,
          col: 2,
          width: DashboardWidth.third,
        ),
      ]);

      expect(
        layout.enabledDirections('right'),
        contains(DashboardMoveDirection.down),
      );

      final moved = layout.nudge('right', DashboardMoveDirection.down);
      expect(moved, isNotNull);
      expect(moved!.rowCount, 2);
      expect(moved.byId('right')!.row, 1);
      expect(moved.byId('right')!.col, 2);
      expect(moved.byId('left')!.row, 0);
      _expectValidGrid(moved.placements);

      // And now `left` has room to grow, which was the point.
      final grown = moved.resize('left', DashboardWidth.full);
      expect(grown, isNotNull);
      expect(grown!.byId('left')!.width, DashboardWidth.full);
    });

    test('a tile alone on the bottom row cannot be nudged down', () {
      // It would vacate its row, the collapse would renumber the new row back
      // to the old index, and nothing would have moved.
      final layout = DashboardGridLayout.fromPlacements(const [
        WidgetPlacement(id: 'top', row: 0, col: 0, width: DashboardWidth.full),
        WidgetPlacement(
          id: 'alone',
          row: 1,
          col: 0,
          width: DashboardWidth.third,
        ),
      ]);

      expect(layout.nudge('alone', DashboardMoveDirection.down), isNull);
      expect(
        layout.enabledDirections('alone'),
        isNot(contains(DashboardMoveDirection.down)),
      );
      // Moving down onto an existing row is unaffected.
      expect(layout.nudge('top', DashboardMoveDirection.down), isNull);
    });

    test('content option replacement preserves layout and clears stale keys', () {
      final updated = mergeWidgetOptions(
        '{"title":"Old","aggregation":"sum","background":{"mode":"fixed"},"layout":{"row":2,"col":4},"futureKey":true}',
        {'title': 'New', 'limit': 8},
      );

      expect(updated, contains('"title":"New"'));
      expect(updated, contains('"limit":8'));
      expect(updated, contains('"layout":{"row":2,"col":4}'));
      expect(updated, contains('"futureKey":true'));
      expect(updated, isNot(contains('aggregation')));
      expect(updated, isNot(contains('background')));
    });
  });
}

void _expectValidGrid(List<WidgetPlacement> placements) {
  final occupied = <(int, int), String>{};
  for (final placement in placements) {
    expect(placement.row, greaterThanOrEqualTo(0));
    expect(placement.col, greaterThanOrEqualTo(0));
    expect(placement.endCol, lessThanOrEqualTo(dashboardGridUnits));
    for (var unit = placement.col; unit < placement.endCol; unit++) {
      expect(
        occupied[(placement.row, unit)],
        isNull,
        reason: '${placement.id} overlaps row ${placement.row}, unit $unit',
      );
      occupied[(placement.row, unit)] = placement.id;
    }
  }
}
