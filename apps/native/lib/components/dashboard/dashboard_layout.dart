import 'package:app/components/dashboard/dashboard_models.dart';

/// A directional one-cell move, used by the floating menu's arrow buttons.
enum DashboardMoveDirection { up, down, left, right }

/// One widget's resolved position on the manual grid: it occupies [width]'s
/// units starting at column [col] on [row]. The half-open unit range it covers
/// is `[col, endCol)`.
class WidgetPlacement {
  const WidgetPlacement({
    required this.id,
    required this.row,
    required this.col,
    required this.width,
  });

  final String id;
  final int row;
  final int col;
  final DashboardWidth width;

  int get units => width.units;

  /// Exclusive end column: the first unit *after* this widget.
  int get endCol => col + units;

  WidgetPlacement copyWith({int? row, int? col, DashboardWidth? width}) =>
      WidgetPlacement(
        id: id,
        row: row ?? this.row,
        col: col ?? this.col,
        width: width ?? this.width,
      );
}

/// The input to [resolvePlacements]: a widget's id and width plus its stored
/// [coord] (null when it predates manual layout). The list must be in display
/// order (by `position`) so the legacy auto-flow fallback reproduces the old
/// layout exactly.
class PlacementInput {
  const PlacementInput({
    required this.id,
    required this.width,
    required this.coord,
  });

  final String id;
  final DashboardWidth width;
  final DashboardLayoutCoord? coord;
}

/// Resolves stored coordinates for [inputs] into placements. When every widget
/// has a stored coordinate we honor them; if *any* is missing we derive the
/// whole layout from the legacy auto-flow so a not-yet-migrated dashboard (or a
/// transient mixed state) renders consistently. The first manual move then
/// persists coordinates for all widgets, flipping the dashboard to the
/// all-stored branch for good.
List<WidgetPlacement> resolvePlacements(List<PlacementInput> inputs) {
  final allStored = inputs.every((i) => i.coord != null);
  if (allStored) {
    return [
      for (final i in inputs)
        WidgetPlacement(
          id: i.id,
          row: i.coord!.row,
          col: i.coord!.col,
          width: i.width,
        ),
    ];
  }
  return _legacyFlow(inputs);
}

/// Reproduces the original auto-flow packing: narrower widths flow left-to-right
/// and wrap into rows; a `full` width always takes its own row.
List<WidgetPlacement> _legacyFlow(List<PlacementInput> inputs) {
  final out = <WidgetPlacement>[];
  var row = 0;
  var used = 0;
  for (final input in inputs) {
    final units = input.width.units;
    if (units >= dashboardGridUnits) {
      if (used > 0) {
        row++;
        used = 0;
      }
      out.add(
        WidgetPlacement(id: input.id, row: row, col: 0, width: input.width),
      );
      row++;
      continue;
    }
    if (used + units > dashboardGridUnits) {
      row++;
      used = 0;
    }
    out.add(
      WidgetPlacement(id: input.id, row: row, col: used, width: input.width),
    );
    used += units;
    if (used == dashboardGridUnits) {
      row++;
      used = 0;
    }
  }
  return out;
}

/// An immutable snapshot of the manual grid. Every mutating operation returns a
/// new, normalized layout (empty rows collapsed, rows renumbered contiguously,
/// placements sorted by row then column) — or null when the move is invalid, so
/// callers can no-op without persisting.
class DashboardGridLayout {
  DashboardGridLayout._(this.placements);

  /// Sorted by (row, col); rows are contiguous from 0.
  final List<WidgetPlacement> placements;

  factory DashboardGridLayout.fromPlacements(List<WidgetPlacement> input) =>
      DashboardGridLayout._(_normalize(input));

  int get rowCount => placements.isEmpty ? 0 : placements.last.row + 1;

  WidgetPlacement? byId(String id) {
    for (final p in placements) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<WidgetPlacement> rowItems(int row) => [
    for (final p in placements)
      if (p.row == row) p,
  ];

  /// Per-unit occupancy of [row]: `true` where a widget sits. The widget
  /// [ignoreId] (the one being moved) is treated as absent so it never blocks
  /// its own destination.
  List<bool> _occupancy(int row, {String? ignoreId}) {
    final occupied = List<bool>.filled(dashboardGridUnits, false);
    for (final p in placements) {
      if (p.row != row || p.id == ignoreId) continue;
      for (var u = p.col; u < p.endCol && u < dashboardGridUnits; u++) {
        occupied[u] = true;
      }
    }
    return occupied;
  }

  /// The widest width that fits starting at ([row], [col]) — i.e. the run of
  /// free units from [col] up to the next occupied unit or the grid edge.
  /// Null when [col] is out of range or already occupied.
  DashboardWidth? fitWidth(int row, int col, {String? ignoreId}) {
    if (col < 0 || col >= dashboardGridUnits) return null;
    final occupied = _occupancy(row, ignoreId: ignoreId);
    if (occupied[col]) return null;
    var free = 0;
    for (var u = col; u < dashboardGridUnits && !occupied[u]; u++) {
      free++;
    }
    return dashboardWidthForUnits(free);
  }

  /// Whether the half-open unit range `[col, col + units)` is fully free on
  /// [row] (and within the grid).
  bool _spanFree(int row, int col, int units, {String? ignoreId}) {
    if (col < 0 || col + units > dashboardGridUnits) return false;
    final occupied = _occupancy(row, ignoreId: ignoreId);
    for (var u = col; u < col + units; u++) {
      if (occupied[u]) return false;
    }
    return true;
  }

  /// Moves [id] to ([row], [col]) with an optional new [width]. Returns null if
  /// the destination span isn't free. Callers that want auto-shrink should pass
  /// the [width] from [fitWidth].
  DashboardGridLayout? place(
    String id,
    int row,
    int col, {
    DashboardWidth? width,
  }) {
    final current = byId(id);
    if (current == null) return null;
    final w = width ?? current.width;
    if (!_spanFree(row, col, w.units, ignoreId: id)) return null;
    return _withReplaced(current.copyWith(row: row, col: col, width: w));
  }

  /// Inserts a brand-new row at [rowIndex] (shifting rows at/after it down) and
  /// drops [id] onto it at [col]. Used by the between-rows drop zones.
  DashboardGridLayout? insertRowAt(String id, int rowIndex, {int col = 0}) {
    final current = byId(id);
    if (current == null) return null;
    final shifted = [
      for (final p in placements)
        if (p.id == id)
          p
        else if (p.row >= rowIndex)
          p.copyWith(row: p.row + 1)
        else
          p,
    ];
    final moved = [
      for (final p in shifted)
        if (p.id == id) p.copyWith(row: rowIndex, col: col) else p,
    ];
    return DashboardGridLayout.fromPlacements(moved);
  }

  /// Whether [row] has room to wedge in another tile: at least one `third`
  /// (the narrowest width) of free units once [ignoreId] is set aside. Drives
  /// the enabled state of the row's vertical insert strips.
  bool canInsertInRow(int row, String ignoreId) {
    final used = placements
        .where((p) => p.row == row && p.id != ignoreId)
        .fold<int>(0, (sum, p) => sum + p.units);
    return dashboardGridUnits - used >= DashboardWidth.third.units;
  }

  /// Wedges [id] into [row] at the ordinal [slot] (0 = before the first tile,
  /// N = after the last), shifting the row's other tiles aside and re-flowing
  /// them flush left-to-right. The inserted tile auto-shrinks to the free span
  /// when it's too wide. Returns null when the row has no room (see
  /// [canInsertInRow]). The tile's old row collapses if it empties.
  DashboardGridLayout? insertInRow(String id, int row, int slot) {
    final current = byId(id);
    if (current == null) return null;
    final rowTiles = [
      for (final p in placements)
        if (p.row == row && p.id != id) p,
    ]..sort((a, b) => a.col.compareTo(b.col));
    final usedUnits = rowTiles.fold<int>(0, (sum, p) => sum + p.units);
    final freeUnits = dashboardGridUnits - usedUnits;
    if (freeUnits < DashboardWidth.third.units) return null;
    // Shrink only when the tile can't fit the free span as-is.
    final width = current.units <= freeUnits
        ? current.width
        : dashboardWidthForUnits(freeUnits)!;

    final ordered = [...rowTiles];
    ordered.insert(
      slot.clamp(0, ordered.length),
      current.copyWith(width: width),
    );

    final reflowed = <WidgetPlacement>[];
    var col = 0;
    for (final p in ordered) {
      reflowed.add(p.copyWith(row: row, col: col));
      col += p.width.units;
    }
    final others = [
      for (final p in placements)
        if (p.row != row && p.id != id) p,
    ];
    return DashboardGridLayout.fromPlacements([...others, ...reflowed]);
  }

  /// Swaps the positions of [aId] and [bId] (used when a widget is dropped onto
  /// another). Returns null unless each fits in the other's slot without
  /// overlapping a third widget.
  DashboardGridLayout? swap(String aId, String bId) {
    if (aId == bId) return null;
    final a = byId(aId);
    final b = byId(bId);
    if (a == null || b == null) return null;
    final ignore = {aId, bId};
    if (!_spanFreeIgnoring(b.row, b.col, a.units, ignore)) return null;
    if (!_spanFreeIgnoring(a.row, a.col, b.units, ignore)) return null;
    return DashboardGridLayout.fromPlacements([
      for (final p in placements)
        if (p.id == aId)
          p.copyWith(row: b.row, col: b.col)
        else if (p.id == bId)
          p.copyWith(row: a.row, col: a.col)
        else
          p,
    ]);
  }

  bool _spanFreeIgnoring(int row, int col, int units, Set<String> ignoreIds) {
    if (col < 0 || col + units > dashboardGridUnits) return false;
    final occupied = List<bool>.filled(dashboardGridUnits, false);
    for (final p in placements) {
      if (p.row != row || ignoreIds.contains(p.id)) continue;
      for (var u = p.col; u < p.endCol && u < dashboardGridUnits; u++) {
        occupied[u] = true;
      }
    }
    for (var u = col; u < col + units; u++) {
      if (occupied[u]) return false;
    }
    return true;
  }

  /// One-cell nudge in [direction]. Horizontal moves slide by a single unit into
  /// adjacent free space; vertical moves jump to the same column on the
  /// neighboring row when it's free. Returns null when blocked or out of bounds
  /// (so the matching arrow button can disable).
  DashboardGridLayout? nudge(String id, DashboardMoveDirection direction) {
    final p = byId(id);
    if (p == null) return null;
    return switch (direction) {
      DashboardMoveDirection.left =>
        _spanFree(p.row, p.col - 1, p.units, ignoreId: id)
            ? place(id, p.row, p.col - 1)
            : null,
      DashboardMoveDirection.right =>
        _spanFree(p.row, p.col + 1, p.units, ignoreId: id)
            ? place(id, p.row, p.col + 1)
            : null,
      DashboardMoveDirection.up =>
        p.row > 0 && _spanFree(p.row - 1, p.col, p.units, ignoreId: id)
            ? place(id, p.row - 1, p.col)
            : null,
      DashboardMoveDirection.down =>
        p.row < rowCount - 1 &&
                _spanFree(p.row + 1, p.col, p.units, ignoreId: id)
            ? place(id, p.row + 1, p.col)
            : null,
    };
  }

  /// The set of directions [id] can currently be nudged in (drives which arrow
  /// buttons are enabled).
  Set<DashboardMoveDirection> enabledDirections(String id) => {
    for (final d in DashboardMoveDirection.values)
      if (nudge(id, d) != null) d,
  };

  /// Re-fits [id] to [width], keeping its column when the wider span is free,
  /// otherwise sliding left to the nearest free span, and finally clamping the
  /// width down to whatever fits at its column. Never overlaps a neighbor.
  DashboardGridLayout? resize(String id, DashboardWidth width) {
    final current = byId(id);
    if (current == null) return null;
    final units = width.units;
    // Keep the current column if the new span fits there.
    if (_spanFree(current.row, current.col, units, ignoreId: id)) {
      return _withReplaced(current.copyWith(width: width));
    }
    // Otherwise slide left to the nearest column with a free span of [units].
    for (var col = current.col - 1; col >= 0; col--) {
      if (_spanFree(current.row, col, units, ignoreId: id)) {
        return _withReplaced(current.copyWith(col: col, width: width));
      }
    }
    // Can't grow without overlapping: clamp to the widest width that fits.
    final fit = fitWidth(current.row, current.col, ignoreId: id);
    if (fit == null || fit == current.width) return null;
    return _withReplaced(current.copyWith(width: fit));
  }

  DashboardGridLayout _withReplaced(WidgetPlacement replacement) =>
      DashboardGridLayout.fromPlacements([
        for (final p in placements)
          if (p.id == replacement.id) replacement else p,
      ]);

  static int _compare(WidgetPlacement a, WidgetPlacement b) {
    final byRow = a.row.compareTo(b.row);
    return byRow != 0 ? byRow : a.col.compareTo(b.col);
  }

  /// Collapses empty rows (renumbering the rest contiguously) and sorts.
  static List<WidgetPlacement> _normalize(List<WidgetPlacement> input) {
    final usedRows = input.map((p) => p.row).toSet().toList()..sort();
    final remap = {for (var i = 0; i < usedRows.length; i++) usedRows[i]: i};
    final out = [for (final p in input) p.copyWith(row: remap[p.row])];
    out.sort(_compare);
    return out;
  }
}
