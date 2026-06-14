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
    this.onTapItem,
    this.onLongPressItem,
  });

  final List<DashboardViewItem> items;
  final ValueChanged<DashboardViewItem>? onTapItem;
  final ValueChanged<DashboardViewItem>? onLongPressItem;
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
                        flex: rows[rowIndex].items[itemIndex].units,
                        child: _buildInteractiveItem(
                          context,
                          rows[rowIndex].items[itemIndex].item,
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

  Widget _buildInteractiveItem(BuildContext context, DashboardViewItem item) {
    return Material(
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
