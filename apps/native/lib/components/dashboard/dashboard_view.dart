import 'package:app/components/dashboard/balance_card_widget.dart';
import 'package:app/components/dashboard/breakdown_chart_widget.dart';
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

/// Renders the dashboard as one flat ordered flow: each widget keeps a position
/// and width, while this view groups the flow into visual rows. The data model
/// stays flat; row grouping is only a rendering detail for compact gaps.
class DashboardView extends StatelessWidget {
  const DashboardView({
    super.key,
    required this.items,
    this.editing = false,
    this.selectedItemId,
    this.onTapItem,
    this.onLongPressItem,
    this.onMoveItem,
    this.onWidthChanged,
    this.onEditItem,
    this.onDeleteItem,
  });

  final List<DashboardViewItem> items;
  final bool editing;
  final String? selectedItemId;
  final ValueChanged<DashboardViewItem>? onTapItem;
  final ValueChanged<DashboardViewItem>? onLongPressItem;
  final void Function(String draggedId, String targetId)? onMoveItem;
  final void Function(DashboardViewItem item, DashboardWidth width)?
  onWidthChanged;
  final ValueChanged<DashboardViewItem>? onEditItem;
  final ValueChanged<DashboardViewItem>? onDeleteItem;
  static const _gridUnits = 6;
  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final rows = _buildRows(maxWidth);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
              if (rowIndex > 0) const SizedBox(height: _gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var itemIndex = 0;
                      itemIndex < rows[rowIndex].items.length;
                      itemIndex++
                    ) ...[
                      if (itemIndex > 0) const SizedBox(width: _gap),
                      Expanded(
                        key: ValueKey(
                          rows[rowIndex].items[itemIndex].item.row.id,
                        ),
                        flex: rows[rowIndex].items[itemIndex].units,
                        child: _buildInteractiveItem(
                          context,
                          rows[rowIndex].items[itemIndex].item,
                          maxWidth *
                              rows[rowIndex].items[itemIndex].units /
                              _gridUnits,
                          // Anchor the floating menu to the side the tile sits
                          // on so a natural-width menu never runs off-screen.
                          menuAlignRight: _alignMenuRight(
                            rows[rowIndex],
                            itemIndex,
                          ),
                        ),
                      ),
                    ],
                    if (rows[rowIndex].remainingUnits > 0)
                      Expanded(
                        flex: rows[rowIndex].remainingUnits,
                        child: const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  List<_DashboardRow> _buildRows(double maxWidth) {
    final rows = <_DashboardRow>[];
    var current = <_DashboardRowItem>[];
    var usedUnits = 0;

    void flush() {
      if (current.isEmpty) return;
      rows.add(_DashboardRow(_normalizedRowItems(current, usedUnits)));
      current = <_DashboardRowItem>[];
      usedUnits = 0;
    }

    for (final item in items) {
      final units = _tileUnits(maxWidth, item.spec.width);
      if (units == _gridUnits) {
        flush();
        rows.add(_DashboardRow([_DashboardRowItem(item, units)]));
        continue;
      }

      if (usedUnits + units > _gridUnits) flush();
      current.add(_DashboardRowItem(item, units));
      usedUnits += units;
      if (usedUnits == _gridUnits) flush();
    }
    flush();
    return rows;
  }

  /// Avoids awkward incomplete rows like half + third or third + third. The
  /// stored width remains unchanged; this is only a visual promotion.
  List<_DashboardRowItem> _normalizedRowItems(
    List<_DashboardRowItem> items,
    int usedUnits,
  ) {
    if (usedUnits == 4 &&
        items.length == 2 &&
        items.every((item) => item.units == 2)) {
      return [for (final item in items) _DashboardRowItem(item.item, 3)];
    }

    if (usedUnits != _gridUnits - 1) return items;

    final promotableIndex = items.indexWhere((item) => item.units == 2);
    if (promotableIndex == -1) return items;

    return [
      for (var i = 0; i < items.length; i++)
        i == promotableIndex ? _DashboardRowItem(items[i].item, 3) : items[i],
    ];
  }

  int _tileUnits(double maxWidth, DashboardWidth width) {
    return switch (width) {
      DashboardWidth.full => _gridUnits,
      DashboardWidth.twoThirds => maxWidth < 360 ? _gridUnits : 4,
      DashboardWidth.half => maxWidth < 320 ? _gridUnits : 3,
      DashboardWidth.third => maxWidth < 300 ? _gridUnits : 2,
    };
  }

  /// Whether the item at [itemIndex] sits on the right half of its row. The
  /// floating menu anchors to that side so its natural width grows toward the
  /// center of the screen instead of running off the edge.
  bool _alignMenuRight(_DashboardRow row, int itemIndex) {
    var leading = 0;
    for (var i = 0; i < itemIndex; i++) {
      leading += row.items[i].units;
    }
    final center = leading + row.items[itemIndex].units / 2;
    return center > _gridUnits / 2;
  }

  Widget _buildInteractiveItem(
    BuildContext context,
    DashboardViewItem item,
    double estimatedWidth, {
    required bool menuAlignRight,
  }) {
    final selected = editing && selectedItemId == item.row.id;
    final hasMenu =
        onWidthChanged != null || onEditItem != null || onDeleteItem != null;
    final menu = hasMenu
        ? _DashboardFloatingMenu(
            width: item.spec.width,
            onWidthChanged: onWidthChanged == null
                ? null
                : (width) => onWidthChanged!(item, width),
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

    final canReorder = editing && onMoveItem != null;

    final dragTarget = DragTarget<String>(
      onWillAcceptWithDetails: canReorder
          ? (details) => details.data != item.row.id
          : null,
      onAcceptWithDetails: canReorder
          ? (details) => onMoveItem!(details.data, item.row.id)
          : null,
      builder: (context, candidateData, rejectedData) {
        final hovering = canReorder && candidateData.isNotEmpty;
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
      alignRight: menuAlignRight,
      menu: menu,
      child: LongPressDraggable<String>(
        data: item.row.id,
        maxSimultaneousDrags: canReorder ? null : 0,
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
    this.onWidthChanged,
    this.onEdit,
    this.onDelete,
  });

  final DashboardWidth width;
  final ValueChanged<DashboardWidth>? onWidthChanged;
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
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
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

class _DashboardRow {
  const _DashboardRow(this.items);

  final List<_DashboardRowItem> items;

  int get remainingUnits =>
      DashboardView._gridUnits -
      items.fold<int>(0, (sum, item) => sum + item.units);
}

class _DashboardRowItem {
  const _DashboardRowItem(this.item, this.units);

  final DashboardViewItem item;
  final int units;
}
