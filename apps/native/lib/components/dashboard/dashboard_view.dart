import 'dart:math' as math;

import 'package:app/components/dashboard/balance_card_widget.dart';
import 'package:app/components/dashboard/balance_comparison_widget.dart';
import 'package:app/components/dashboard/breakdown_chart_widget.dart';
import 'package:app/components/dashboard/dashboard_layout.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/components/dashboard/stat_widget.dart';
import 'package:app/components/dashboard/transaction_list_widget.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DashboardViewItem {
  const DashboardViewItem({required this.row, required this.spec});

  final DashboardWidget row;
  final DashboardWidgetSpec spec;
}

/// Renders the dashboard as a manual grid: each widget keeps an explicit
/// `(row, col)` placement (stored in its `options`) plus a `width`. The user
/// places tiles freely — empty horizontal gaps are allowed, only empty *rows*
/// collapse. Dropping a tile onto an empty cell auto-shrinks it to fit; dropping
/// between rows creates a new row. See [DashboardGridLayout] for the engine.
class DashboardView extends StatelessWidget {
  const DashboardView({
    super.key,
    required this.items,
    this.editing = false,
    this.selectedItemId,
    this.onTapItem,
    this.onLongPressItem,
    this.onPlaceInCell,
    this.onSwap,
    this.onInsertRow,
    this.onInsertInRow,
    this.onAddWidget,
    this.onNudge,
    this.onWidthChanged,
    this.onEditItem,
    this.onDeleteItem,
  });

  final List<DashboardViewItem> items;
  final bool editing;
  final String? selectedItemId;
  final ValueChanged<DashboardViewItem>? onTapItem;
  final ValueChanged<DashboardViewItem>? onLongPressItem;

  /// Places [draggedId] at the empty cell ([row], [col]) with [width] — the
  /// largest width that fits the free span there (auto-shrink to a smaller
  /// area), already computed by the view.
  final void Function(String draggedId, int row, int col, DashboardWidth width)?
  onPlaceInCell;

  /// Swaps the dropped widget with the widget it was dropped onto.
  final void Function(String draggedId, String targetId)? onSwap;

  /// Inserts a new row at [rowIndex] and drops [draggedId] onto it.
  final void Function(String draggedId, int rowIndex)? onInsertRow;

  /// Wedges [draggedId] into [row] at the ordinal [slot] (between two tiles or
  /// at a flush row edge), shifting the row's other tiles aside.
  final void Function(String draggedId, int row, int slot)? onInsertInRow;

  /// Adds a brand-new widget at the empty cell ([row], [col]). [maxUnits] is the
  /// free span there, so the add flow can cap the new widget's width to fit.
  final void Function(int row, int col, int maxUnits)? onAddWidget;

  /// One-cell directional move from the floating menu's arrow buttons.
  final void Function(DashboardViewItem item, DashboardMoveDirection direction)?
  onNudge;

  final void Function(DashboardViewItem item, DashboardWidth width)?
  onWidthChanged;
  final ValueChanged<DashboardViewItem>? onEditItem;
  final ValueChanged<DashboardViewItem>? onDeleteItem;

  static const _gap = 4.0;

  /// Reflow on wide layouts: several 6-unit logical rows render side by side
  /// per visual band once each can get at least this width, so tiles keep a
  /// phone-like size instead of stretching. Capped at [_maxBandColumns].
  static const _minLogicalRowWidth = 380.0;
  static const _bandGap = 16.0;
  static const _maxBandColumns = 3;

  /// Hit width of the (overlaid) between-tile insert strips. Wider than [_gap]
  /// so the seam is easy to hit while dragging, but it lives in a Stack overlay
  /// so it never widens the row's actual layout.
  static const _insertHit = 22.0;

  /// Hit height of the (overlaid) new-row drop bands at each row's top/bottom
  /// edge. Overlaid, so it doesn't change the between-row spacing.
  static const _rowBand = 16.0;

  /// Height of the spare row kept below the board while editing. Shorter than a
  /// tile — it reads as somewhere to put things, not as a widget.
  static const _spareRowHeight = 88.0;

  /// While editing, one empty row is always kept below the board. Without it a
  /// tile on the bottom row has nowhere to go, so a neighbor that wants to grow
  /// can never be moved out of the way. It only becomes a real row once
  /// something lands in it.
  bool get _hasSpareRow => editing && onPlaceInCell != null;

  @override
  Widget build(BuildContext context) {
    final layout = DashboardGridLayout.fromPlacements(
      resolvePlacements([
        for (final item in items)
          PlacementInput(
            id: item.row.id,
            width: item.spec.width,
            coord: dashboardLayoutFromOptions(item.row.options),
          ),
      ]),
    );
    final itemsById = {for (final item in items) item.row.id: item};

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final rowCount = layout.rowCount + (_hasSpareRow ? 1 : 0);
        // Reflow, don't stretch: logical (row, col) coordinates — and the
        // persisted layout — always stay in 6-unit terms; wide layouts only
        // change how many logical rows sit side by side per visual band.
        final bandColumns = math.min(
          _maxBandColumns,
          math.max(
            1,
            (maxWidth + _bandGap) ~/ (_minLogicalRowWidth + _bandGap),
          ),
        );
        if (bandColumns == 1) {
          // Identical spacing in view and edit mode (a constant [_gap] between
          // rows, nothing at the edges) so toggling edit never shifts the
          // layout. The new-row drop bands are overlaid inside each row (see
          // _buildRow).
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var row = 0; row < rowCount; row++) ...[
                if (row > 0) const SizedBox(height: _gap),
                _buildRow(context, layout, itemsById, row, maxWidth),
              ],
            ],
          );
        }
        final logicalRowWidth =
            (maxWidth - _bandGap * (bandColumns - 1)) / bandColumns;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var band = 0; band * bandColumns < rowCount; band++) ...[
              if (band > 0) const SizedBox(height: _gap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < bandColumns; i++) ...[
                    if (i > 0) const SizedBox(width: _bandGap),
                    SizedBox(
                      width: logicalRowWidth,
                      child: band * bandColumns + i < rowCount
                          ? _buildRow(
                              context,
                              layout,
                              itemsById,
                              band * bandColumns + i,
                              logicalRowWidth,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    DashboardGridLayout layout,
    Map<String, DashboardViewItem> itemsById,
    int row,
    double maxWidth,
  ) {
    // Fixed 6-column grid: every unit is exactly [unitWidth], every column
    // boundary exactly [_gap]. Tiles and gaps are sized from this, so a tile of
    // a given width is pixel-identical in every row, and the layout is the same
    // whether editing or not (drop affordances are painted/overlaid, never
    // inserted into the flow — no shift when toggling edit mode).
    final unitWidth =
        (maxWidth - _gap * (dashboardGridUnits - 1)) / dashboardGridUnits;
    double span(int units) => units * unitWidth + (units - 1) * _gap;
    double columnLeft(int col) => col * (unitWidth + _gap);

    // The spare row sits one past the real ones and holds nothing, so its whole
    // width is a single empty run.
    final isSpare = row >= layout.rowCount;
    final rowItems = layout.rowItems(row);

    // Base flow: tiles and (in edit mode) dashed gap placeholders, at exact
    // widths, separated by a constant [_gap].
    final base = <Widget>[];
    void addGap(int from, int to) {
      if (to <= from) return;
      if (base.isNotEmpty) base.add(const SizedBox(width: _gap));
      base.add(
        SizedBox(
          width: span(to - from),
          child: _gapPlaceholder(context, layout, row, from, to),
        ),
      );
    }

    var unit = 0;
    for (final placement in rowItems) {
      addGap(unit, placement.col);
      if (base.isNotEmpty) base.add(const SizedBox(width: _gap));
      final item = itemsById[placement.id];
      base.add(
        SizedBox(
          key: ValueKey(placement.id),
          width: span(placement.units),
          child: item == null
              ? const SizedBox.shrink()
              : _buildInteractiveItem(
                  context,
                  item,
                  placement,
                  layout,
                  span(placement.units),
                ),
        ),
      );
      unit = placement.endCol;
    }
    addGap(unit, dashboardGridUnits);

    final baseRow = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: base,
    );

    // Nothing in the spare row has an intrinsic height, so it gets a fixed one
    // or it would be an invisible, unhittable strip. It has to be *tight*: a
    // `minHeight`-only constraint leaves the maximum unbounded, and the row's
    // [CrossAxisAlignment.stretch] then asks for infinite height.
    Widget sized(Widget child) => isSpare
        ? SizedBox(height: _spareRowHeight, child: child)
        : IntrinsicHeight(child: child);

    final canInsertInRow = editing && onInsertInRow != null && !isSpare;
    // The spare row *is* the row below the board, so it paints no band of its
    // own, and the last real row drops its bottom band — the spare row already
    // does that job, and more legibly.
    final canInsertRow = editing && onInsertRow != null && !isSpare;
    if (!canInsertInRow && !canInsertRow) {
      return sized(baseRow);
    }

    // All drop affordances live in a Stack overlay so their generous hit areas
    // never change the row's actual size (no layout shift when editing).
    final overlay = <Widget>[];

    // Between-tile insert strips (and flush row edges): wedge into this row.
    if (canInsertInRow) {
      Widget strip(double centerX, int slot) => Positioned(
        left: centerX - _insertHit / 2,
        width: _insertHit,
        top: 0,
        bottom: 0,
        child: _RowInsertZone(
          onAccept: (draggedId) => onInsertInRow!(draggedId, row, slot),
          enabled: (draggedId) => layout.canInsertInRow(row, draggedId),
        ),
      );
      for (var i = 0; i < rowItems.length; i++) {
        final placement = rowItems[i];
        if (i == 0 && placement.col == 0) {
          overlay.add(strip(0, 0));
        }
        if (i > 0 && rowItems[i - 1].endCol == placement.col) {
          overlay.add(strip(columnLeft(placement.col) - _gap / 2, i));
        }
        if (i == rowItems.length - 1 &&
            placement.endCol == dashboardGridUnits) {
          overlay.add(strip(maxWidth, rowItems.length));
        }
      }
    }

    // New-row drop bands at the row's top edge (insert a row above) and, for the
    // last row, its bottom edge (insert a row below). Overlaid at the edges so
    // the between-row spacing matches view mode exactly.
    if (canInsertRow) {
      overlay.add(
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _rowBand,
          child: _NewRowDropZone(
            alignment: Alignment.topCenter,
            onAccept: (draggedId) => onInsertRow!(draggedId, row),
          ),
        ),
      );
      if (row == layout.rowCount - 1 && !_hasSpareRow) {
        overlay.add(
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: _rowBand,
            child: _NewRowDropZone(
              alignment: Alignment.bottomCenter,
              onAccept: (draggedId) => onInsertRow!(draggedId, row + 1),
            ),
          ),
        );
      }
    }

    return sized(Stack(children: [baseRow, ...overlay]));
  }

  /// A contiguous run of empty units. In editing mode it renders as one merged
  /// dashed placeholder (tap to add a widget here) with a per-unit drop target
  /// overlay, so a dropped tile still lands on the exact unit under the pointer
  /// and auto-shrinks to the free run. Outside editing it's just reserved space
  /// keeping the tiles aligned.
  Widget _gapPlaceholder(
    BuildContext context,
    DashboardGridLayout layout,
    int row,
    int from,
    int to,
  ) {
    if (!editing || onPlaceInCell == null) return const SizedBox.shrink();
    final span = to - from;
    // A run can only hold a widget when it's at least a `1/3` (2 units) wide;
    // narrower runs still show the dashed cell but can't be added/dropped into.
    final canHold = dashboardWidthForUnits(span) != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: _GapVisual(
            onAdd: canHold && onAddWidget != null
                ? () => onAddWidget!(row, from, span)
                : null,
          ),
        ),
        Positioned.fill(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var u = from; u < to; u++) ...[
                if (u > from) const SizedBox(width: _gap),
                Expanded(
                  child: _UnitDropTarget(
                    row: row,
                    unit: u,
                    layout: layout,
                    onPlace: onPlaceInCell!,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Whether the tile at [placement] sits on the right half of its row, so the
  /// floating menu anchors to that side and grows toward the screen center.
  bool _alignMenuRight(WidgetPlacement placement) {
    final center = placement.col + placement.units / 2;
    return center > dashboardGridUnits / 2;
  }

  Widget _buildInteractiveItem(
    BuildContext context,
    DashboardViewItem item,
    WidgetPlacement placement,
    DashboardGridLayout layout,
    double estimatedWidth,
  ) {
    final selected = editing && selectedItemId == item.row.id;
    final hasMenu =
        onWidthChanged != null ||
        onEditItem != null ||
        onDeleteItem != null ||
        onNudge != null;
    final menu = hasMenu
        ? _DashboardFloatingMenu(
            width: item.spec.width,
            enabledDirections: onNudge == null
                ? const {}
                : layout.enabledDirections(item.row.id),
            onWidthChanged: onWidthChanged == null
                ? null
                : (width) => onWidthChanged!(item, width),
            onMove: onNudge == null
                ? null
                : (direction) => onNudge!(item, direction),
            onEdit: onEditItem == null ? null : () => onEditItem!(item),
            onDelete: onDeleteItem == null ? null : () => onDeleteItem!(item),
          )
        : null;
    final canDrag = editing && (onPlaceInCell != null || onSwap != null);

    final child = _DashboardEditableFrame(
      selected: selected,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // A tile that can be picked up should say so before the pointer goes
          // down; with a mouse the grab cursor is the only hint that edit mode
          // supports drag-and-drop at all.
          mouseCursor: canDrag ? SystemMouseCursors.grab : null,
          onTap: onTapItem == null ? null : () => onTapItem!(item),
          onLongPress: onLongPressItem == null
              ? null
              : () => onLongPressItem!(item),
          child: _buildWidget(item.spec),
        ),
      ),
    );

    final canSwap = editing && onSwap != null;

    final dragTarget = DragTarget<String>(
      onWillAcceptWithDetails: canSwap
          ? (details) => details.data != item.row.id
          : null,
      onAcceptWithDetails: canSwap
          ? (details) => onSwap!(details.data, item.row.id)
          : null,
      builder: (context, candidateData, rejectedData) {
        final hovering = canSwap && candidateData.isNotEmpty;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: hovering
                ? [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.22),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
    );

    return _FloatingMenuAnchor(
      show: selected,
      alignRight: _alignMenuRight(placement),
      menu: menu,
      child: _MouseFriendlyDraggable<String>(
        data: item.row.id,
        maxSimultaneousDrags: canDrag ? null : 0,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: SizedBox(
          width: estimatedWidth.clamp(
            120,
            MediaQuery.sizeOf(context).width - 32,
          ),
          child: Material(
            color: Colors.transparent,
            elevation: 10,
            borderRadius: BorderRadius.circular(8),
            child: _DashboardEditableFrame(
              selected: true,
              child: _DashboardDragPreview(spec: item.spec),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: dragTarget),
        child: dragTarget,
      ),
    );
  }

  Widget _buildWidget(DashboardWidgetSpec spec) {
    return switch (spec) {
      StatWidgetSpec() => StatWidget(spec: spec),
      TransactionListWidgetSpec() => TransactionListWidget(spec: spec),
      BalanceCardWidgetSpec() => BalanceCardWidget(spec: spec),
      ChartWidgetSpec() => BreakdownChartWidget(spec: spec),
      BalanceComparisonWidgetSpec() => BalanceComparisonWidget(spec: spec),
    };
  }
}

/// A [LongPressDraggable] that a mouse can start dragging straight away.
///
/// Touch (and stylus, and trackpad pans) keep the long-press delay: the
/// dashboard renders inside the home `ListView`, and an immediate touch drag
/// would beat that list's own scroll drag in the gesture arena, leaving the
/// page unscrollable anywhere a tile sits. A mouse has no such conflict —
/// [ScrollBehavior.dragDevices] excludes [PointerDeviceKind.mouse], so
/// press-and-drag with a mouse never scrolls a `Scrollable` — which makes the
/// half-second hold pure friction on desktop.
class _MouseFriendlyDraggable<T extends Object> extends LongPressDraggable<T> {
  const _MouseFriendlyDraggable({
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.maxSimultaneousDrags,
  });

  @override
  DelayedMultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    final recognizer = _MouseImmediateMultiDragGestureRecognizer(
      delay: delay,
      allowedButtonsFilter: allowedButtonsFilter,
    );
    return recognizer
      ..onStart = (Offset position) {
        final result = onStart(position);
        // Same contract as [LongPressDraggable], minus the buzz for a pointer
        // that never waited out a long press to get here.
        if (result != null &&
            hapticFeedbackOnStart &&
            recognizer.lastPointerKind != PointerDeviceKind.mouse) {
          HapticFeedback.selectionClick();
        }
        return result;
      };
  }
}

/// [DelayedMultiDragGestureRecognizer] that drops the delay for mouse pointers
/// and keeps it for every other device kind.
class _MouseImmediateMultiDragGestureRecognizer
    extends DelayedMultiDragGestureRecognizer {
  _MouseImmediateMultiDragGestureRecognizer({
    required super.delay,
    super.allowedButtonsFilter,
  });

  /// Kind of the most recent pointer this recognizer took charge of. Read back
  /// by [_MouseFriendlyDraggable] to decide whether the drag that just started
  /// earned haptics — `onStart` only carries a position.
  PointerDeviceKind? lastPointerKind;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    lastPointerKind = event.kind;
    if (event.kind != PointerDeviceKind.mouse) {
      return super.createNewPointerState(event);
    }
    return _ImmediateDragPointerState(
      event.position,
      event.kind,
      gestureSettings,
    );
  }
}

/// Per-pointer state that claims the drag as soon as the pointer travels past
/// [_slop] — the mouse counterpart of the framework's private immediate
/// multi-drag state.
class _ImmediateDragPointerState extends MultiDragPointerState {
  _ImmediateDragPointerState(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
  );

  /// Flutter's precise-pointer hit slop is a single logical pixel, which suits
  /// a dedicated drag handle but is far too twitchy for a tile that is *also* a
  /// tap target: a click carrying a pixel of hand jitter would turn into a drag
  /// that lands back on itself (a no-op) and swallow the selection tap. Still
  /// well under [kTouchSlop], so a deliberate mouse drag feels immediate.
  static const double _slop = 6;

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta!.distance > _slop) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) =>
      starter(initialPosition);
}

/// The merged dashed visual filling a contiguous empty run in editing mode. Tap
/// it (or its `+`) to add a new widget there. The dashed outline is light so
/// empty space reads as "available" rather than a heavy box. Drop feedback is
/// handled by the per-unit [_UnitDropTarget]s layered on top.
class _GapVisual extends StatelessWidget {
  const _GapVisual({required this.onAdd});

  /// Null when the run is too narrow to hold a widget — then no `+`/tap.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = CustomPaint(
      painter: _DashedRRectPainter(
        color: scheme.outlineVariant.withValues(alpha: 0.8),
        strokeWidth: 1,
        radius: 8,
      ),
      child: onAdd == null
          ? const SizedBox.expand()
          : Center(
              child: Icon(
                Icons.add_rounded,
                size: 18,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
    );
    return Padding(
      padding: const EdgeInsets.all(2),
      child: onAdd == null
          ? content
          : Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(8),
                child: content,
              ),
            ),
    );
  }
}

/// One empty grid unit's drop target, layered transparently over a [_GapVisual]
/// so dropping lands on the exact unit under the pointer (shrinking the tile to
/// the free run). Lights up only the hovered unit; lets taps fall through to the
/// `+` beneath it.
class _UnitDropTarget extends StatelessWidget {
  const _UnitDropTarget({
    required this.row,
    required this.unit,
    required this.layout,
    required this.onPlace,
  });

  final int row;
  final int unit;
  final DashboardGridLayout layout;
  final void Function(String draggedId, int row, int col, DashboardWidth width)
  onPlace;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          layout.fitWidth(row, unit, ignoreId: details.data) != null,
      onAcceptWithDetails: (details) {
        final dragged = layout.byId(details.data);
        final fit = layout.fitWidth(row, unit, ignoreId: details.data);
        if (dragged == null || fit == null) return;
        // Keep the dragged width unless the free run is narrower (auto-shrink).
        final width = fit.units < dragged.units ? fit : dragged.width;
        onPlace(details.data, row, unit, width);
      },
      builder: (context, candidateData, rejectedData) {
        if (candidateData.isEmpty) return const SizedBox.expand();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.all(2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      },
    );
  }
}

/// Paints a dashed rounded-rectangle border the size of its child. Flutter has
/// no dashed `BoxBorder`, so the stroke is walked manually with [dash]/[gap].
class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double radius;
  static const double dash = 5;
  static const double gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          // Inset by half the stroke so the dashes aren't clipped at the edge.
          Rect.fromLTWH(
            strokeWidth / 2,
            strokeWidth / 2,
            size.width - strokeWidth,
            size.height - strokeWidth,
          ),
          Radius.circular(radius),
        ),
      );
    final dashed = Path();
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        dashed.addPath(metric.extractPath(distance, end), Offset.zero);
        distance += dash + gap;
      }
    }
    canvas.drawPath(
      dashed,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.radius != radius;
}

/// A new-row drop band, overlaid at a row's top or bottom edge. Dropping a tile
/// here inserts a fresh row at that boundary. Invisible until a tile is dragged
/// over it (so it never alters the between-row spacing), then shows a full-width
/// bar at the [alignment] edge to preview the new row.
class _NewRowDropZone extends StatelessWidget {
  const _NewRowDropZone({required this.alignment, required this.onAccept});

  final Alignment alignment;
  final void Function(String draggedId) onAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, rejectedData) {
        if (candidateData.isEmpty) return const SizedBox.expand();
        return Align(
          alignment: alignment,
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      },
    );
  }
}

/// The vertical drop strip between two adjacent tiles (or at a flush row edge).
/// Dropping here wedges the dragged tile into the row at this position, shifting
/// the others aside. Rendered in a Stack overlay (so its hit width never widens
/// the row): invisible until a tile is dragged over it, then a full-height bar
/// previews where the tile will land.
class _RowInsertZone extends StatelessWidget {
  const _RowInsertZone({required this.onAccept, required this.enabled});

  final void Function(String draggedId) onAccept;
  final bool Function(String draggedId) enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => enabled(details.data),
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty;
        return Align(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: hovering ? 4 : 0,
            height: double.infinity,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      },
    );
  }
}

/// Anchors a floating [menu] just below [child] using the app overlay, so the
/// menu paints above every sibling/next-row widget and never shifts the
/// dashboard layout. [CompositedTransformFollower] keeps it pinned to the tile
/// as the home list scrolls. The menu keeps its natural width (it is not
/// clamped to the tile), and anchors to the tile's left or right edge per
/// [alignRight] so it grows toward the screen center instead of off the edge.
class _FloatingMenuAnchor extends StatefulWidget {
  const _FloatingMenuAnchor({
    required this.show,
    required this.alignRight,
    required this.menu,
    required this.child,
  });

  final bool show;
  final bool alignRight;
  final Widget? menu;
  final Widget child;

  @override
  State<_FloatingMenuAnchor> createState() => _FloatingMenuAnchorState();
}

class _FloatingMenuAnchorState extends State<_FloatingMenuAnchor> {
  static const _gap = 6.0;

  final LayerLink _link = LayerLink();
  final OverlayPortalController _controller = OverlayPortalController();

  bool get _shouldShow => widget.show && widget.menu != null;

  @override
  void initState() {
    super.initState();
    _syncOverlay();
  }

  @override
  void didUpdateWidget(_FloatingMenuAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncOverlay();
  }

  /// Toggle the portal after the current frame: [OverlayPortalController.show]
  /// mutates the element tree, which is illegal during build/didUpdateWidget.
  void _syncOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_shouldShow && !_controller.isShowing) {
        _controller.show();
      } else if (!_shouldShow && _controller.isShowing) {
        _controller.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final alignRight = widget.alignRight;
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (context) {
        final menu = widget.menu;
        if (menu == null) return const SizedBox.shrink();
        final anchor = alignRight ? Alignment.topRight : Alignment.topLeft;
        return CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: alignRight
              ? Alignment.bottomRight
              : Alignment.bottomLeft,
          followerAnchor: anchor,
          offset: const Offset(0, _gap),
          // The follower child fills the overlay; aligning the menu to the
          // matching corner places it exactly at the tile's bottom edge while
          // letting it size to its own content.
          child: Align(alignment: anchor, child: menu),
        );
      },
      child: CompositedTransformTarget(link: _link, child: widget.child),
    );
  }
}

class _DashboardDragPreview extends StatelessWidget {
  const _DashboardDragPreview({required this.spec});

  final DashboardWidgetSpec spec;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = switch (spec) {
      StatWidgetSpec(:final title) ||
      TransactionListWidgetSpec(:final title) ||
      BalanceCardWidgetSpec(:final title) ||
      ChartWidgetSpec(:final title) ||
      BalanceComparisonWidgetSpec(:final title) =>
        title.isEmpty
            ? context.l10n.widget
            : context.l10n.dashboardTitle(title),
    };
    final icon = switch (spec) {
      StatWidgetSpec() => Icons.calculate_outlined,
      TransactionListWidgetSpec() => Icons.receipt_long_outlined,
      BalanceCardWidgetSpec() => Icons.account_balance_wallet_outlined,
      ChartWidgetSpec() => Icons.donut_large_rounded,
      BalanceComparisonWidgetSpec() => Icons.compare_arrows_rounded,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.primary.withValues(alpha: 0.06),
          colors.surface,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 128),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardEditableFrame extends StatelessWidget {
  const _DashboardEditableFrame({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.primary, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DashboardFloatingMenu extends StatelessWidget {
  const _DashboardFloatingMenu({
    required this.width,
    required this.enabledDirections,
    this.onWidthChanged,
    this.onMove,
    this.onEdit,
    this.onDelete,
  });

  final DashboardWidth width;
  final Set<DashboardMoveDirection> enabledDirections;
  final ValueChanged<DashboardWidth>? onWidthChanged;
  final ValueChanged<DashboardMoveDirection>? onMove;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface.withValues(alpha: 0.96),
      elevation: 8,
      shadowColor: colors.shadow.withValues(alpha: 0.24),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in DashboardWidth.values)
                  _WidthMenuButton(
                    label: _labelForWidth(option),
                    selected: width == option,
                    onTap: onWidthChanged == null
                        ? null
                        : () => onWidthChanged!(option),
                  ),
                const SizedBox(width: 4),
                // Named via `Icon.semanticLabel` rather than `IconButton`'s
                // `tooltip:`. A tooltip is an `OverlayPortal`, and this menu is
                // itself the overlay child of an `OverlayPortal`
                // ([_FloatingMenuAnchor]); showing a tooltip on hover pushes a
                // second layout-callback overlay child into the same
                // `_RenderTheatre` and trips the framework assertion at
                // rendering/object.dart `scheduleLayoutCallback`
                // (`debugNeedsLayout is not true`). `semanticLabel` keeps these
                // icon-only buttons named for screen readers — `IconButton`'s
                // own `Semantics(button: true)` carries no label — without any
                // overlay. Guarded by a semantics test in
                // test/components/dashboard/dashboard_view_test.dart.
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.tune_rounded,
                    size: 20,
                    semanticLabel: context.l10n.edit,
                  ),
                  onPressed: onEdit,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: colors.error,
                    semanticLabel: context.l10n.remove,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ),
            if (onMove != null) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MoveButton(
                    icon: Icons.arrow_back_rounded,
                    semanticLabel: context.l10n.moveLeft,
                    onPressed:
                        enabledDirections.contains(DashboardMoveDirection.left)
                        ? () => onMove!(DashboardMoveDirection.left)
                        : null,
                  ),
                  _MoveButton(
                    icon: Icons.arrow_upward_rounded,
                    semanticLabel: context.l10n.moveUp,
                    onPressed:
                        enabledDirections.contains(DashboardMoveDirection.up)
                        ? () => onMove!(DashboardMoveDirection.up)
                        : null,
                  ),
                  _MoveButton(
                    icon: Icons.arrow_downward_rounded,
                    semanticLabel: context.l10n.moveDown,
                    onPressed:
                        enabledDirections.contains(DashboardMoveDirection.down)
                        ? () => onMove!(DashboardMoveDirection.down)
                        : null,
                  ),
                  _MoveButton(
                    icon: Icons.arrow_forward_rounded,
                    semanticLabel: context.l10n.moveRight,
                    onPressed:
                        enabledDirections.contains(DashboardMoveDirection.right)
                        ? () => onMove!(DashboardMoveDirection.right)
                        : null,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _labelForWidth(DashboardWidth width) => dashboardWidthLabel(width);
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;

  /// Accessible name for this icon-only button. Deliberately not an
  /// `IconButton.tooltip` — see the note in [_DashboardFloatingMenu].
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20, semanticLabel: semanticLabel),
      onPressed: onPressed,
    );
  }
}

class _WidthMenuButton extends StatelessWidget {
  const _WidthMenuButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.primary : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
