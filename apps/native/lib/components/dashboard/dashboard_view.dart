import 'package:app/components/dashboard/balance_card_widget.dart';
import 'package:app/components/dashboard/breakdown_chart_widget.dart';
import 'package:app/components/dashboard/dashboard_layout.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/components/dashboard/stat_widget.dart';
import 'package:app/components/dashboard/transaction_list_widget.dart';
import 'package:app/database.dart';
import 'package:flutter/material.dart';

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

  /// One-cell directional move from the floating menu's arrow buttons.
  final void Function(DashboardViewItem item, DashboardMoveDirection direction)?
  onNudge;

  final void Function(DashboardViewItem item, DashboardWidth width)?
  onWidthChanged;
  final ValueChanged<DashboardViewItem>? onEditItem;
  final ValueChanged<DashboardViewItem>? onDeleteItem;

  static const _gap = 4.0;

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
        final rowCount = layout.rowCount;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _interRowZone(context, layout, 0),
            for (var row = 0; row < rowCount; row++) ...[
              _buildRow(context, layout, itemsById, row, maxWidth),
              _interRowZone(context, layout, row + 1),
            ],
          ],
        );
      },
    );
  }

  /// The space between (and around) rows. In editing mode every boundary — top,
  /// between, and bottom — is a drop zone that inserts a new row; otherwise only
  /// the gaps between rows reserve the usual spacing.
  Widget _interRowZone(
    BuildContext context,
    DashboardGridLayout layout,
    int rowIndex,
  ) {
    final canDrop = editing && onInsertRow != null;
    if (!canDrop) {
      final isEdge = rowIndex == 0 || rowIndex == layout.rowCount;
      return SizedBox(height: isEdge ? 0 : _gap);
    }
    return _InterRowDropZone(
      onAccept: (draggedId) => onInsertRow!(draggedId, rowIndex),
    );
  }

  Widget _buildRow(
    BuildContext context,
    DashboardGridLayout layout,
    Map<String, DashboardViewItem> itemsById,
    int row,
    double maxWidth,
  ) {
    final rowItems = layout.rowItems(row);
    // Build left-to-right segments: tiles interleaved with gap regions, each
    // sized by its unit span so the grid stays aligned.
    final segments = <Widget>[];

    void addGapRegion(int from, int to) {
      if (to <= from) return;
      segments.add(
        Expanded(
          flex: to - from,
          child: _gapRegion(context, layout, row, from, to),
        ),
      );
    }

    var unit = 0;
    for (final placement in rowItems) {
      addGapRegion(unit, placement.col);
      final item = itemsById[placement.id];
      segments.add(
        Expanded(
          key: ValueKey(placement.id),
          flex: placement.units,
          child: item == null
              ? const SizedBox.shrink()
              : _buildInteractiveItem(
                  context,
                  item,
                  placement,
                  layout,
                  maxWidth * placement.units / dashboardGridUnits,
                ),
        ),
      );
      unit = placement.endCol;
    }
    addGapRegion(unit, dashboardGridUnits);

    final children = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      if (i > 0) children.add(const SizedBox(width: _gap));
      children.add(segments[i]);
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// A contiguous run of empty units. In editing mode each unit becomes its own
  /// drop cell (so a tile can land at any column); otherwise it's just reserved
  /// space that keeps the surrounding tiles aligned.
  Widget _gapRegion(
    BuildContext context,
    DashboardGridLayout layout,
    int row,
    int from,
    int to,
  ) {
    if (!editing || onPlaceInCell == null) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var u = from; u < to; u++)
          Expanded(
            child: _GapDropCell(
              row: row,
              unit: u,
              layout: layout,
              onPlace: onPlaceInCell!,
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
    final child = _DashboardEditableFrame(
      selected: selected,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
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

    final canDrag = editing && (onPlaceInCell != null || onSwap != null);

    return _FloatingMenuAnchor(
      show: selected,
      alignRight: _alignMenuRight(placement),
      menu: menu,
      child: LongPressDraggable<String>(
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
    };
  }
}

/// An empty grid unit in editing mode. Accepts a dropped widget at this cell,
/// shrinking it to the free span when it's wider than the space available.
class _GapDropCell extends StatelessWidget {
  const _GapDropCell({
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
        // Keep the dragged width unless the free span is narrower (auto-shrink
        // to the smaller area).
        final width = fit.units < dragged.units ? fit : dragged.width;
        onPlace(details.data, row, unit, width);
      },
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty;
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.all(2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: hovering
                  ? scheme.primary.withValues(alpha: 0.12)
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              border: Border.all(
                color: hovering ? scheme.primary : scheme.outlineVariant,
                width: hovering ? 2 : 1,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The drop band between two rows. Dropping a widget here splits the layout,
/// inserting a fresh row at this boundary. Expands and shows a line on hover.
class _InterRowDropZone extends StatelessWidget {
  const _InterRowDropZone({required this.onAccept});

  final void Function(String draggedId) onAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: hovering ? 26 : 12,
          alignment: Alignment.center,
          child: hovering
              ? Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              : const SizedBox.shrink(),
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
      ChartWidgetSpec(:final title) => title.isEmpty ? 'Widget' : title,
    };
    final icon = switch (spec) {
      StatWidgetSpec() => Icons.calculate_outlined,
      TransactionListWidgetSpec() => Icons.receipt_long_outlined,
      BalanceCardWidgetSpec() => Icons.account_balance_wallet_outlined,
      ChartWidgetSpec() => Icons.donut_large_rounded,
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
                IconButton(
                  tooltip: 'Editar',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.tune_rounded, size: 20),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'Quitar',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: colors.error,
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
                    tooltip: 'Mover a la izquierda',
                    onPressed:
                        enabledDirections.contains(DashboardMoveDirection.left)
                        ? () => onMove!(DashboardMoveDirection.left)
                        : null,
                  ),
                  _MoveButton(
                    icon: Icons.arrow_upward_rounded,
                    tooltip: 'Mover hacia arriba',
                    onPressed:
                        enabledDirections.contains(DashboardMoveDirection.up)
                        ? () => onMove!(DashboardMoveDirection.up)
                        : null,
                  ),
                  _MoveButton(
                    icon: Icons.arrow_downward_rounded,
                    tooltip: 'Mover hacia abajo',
                    onPressed:
                        enabledDirections.contains(DashboardMoveDirection.down)
                        ? () => onMove!(DashboardMoveDirection.down)
                        : null,
                  ),
                  _MoveButton(
                    icon: Icons.arrow_forward_rounded,
                    tooltip: 'Mover a la derecha',
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

  String _labelForWidth(DashboardWidth width) {
    return switch (width) {
      DashboardWidth.full => '1/1',
      DashboardWidth.twoThirds => '2/3',
      DashboardWidth.half => '1/2',
      DashboardWidth.third => '1/3',
    };
  }
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20),
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
