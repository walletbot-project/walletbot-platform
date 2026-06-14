import 'package:app/components/dashboard/balance_card_widget.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/components/dashboard/stat_widget.dart';
import 'package:app/components/dashboard/transaction_list_widget.dart';
import 'package:flutter/material.dart';

/// Renders the dashboard as one flat ordered flow: each widget is sized by its
/// [DashboardWidth] and laid out with a [Wrap], so narrower tiles flow and wrap
/// into rows (docs/home-dashboard.md "Layout: width, not nested rows"). Keeping
/// it a flat list — rather than nested row containers — is what keeps future
/// reorder and sync simple.
class DashboardView extends StatelessWidget {
  const DashboardView({super.key, required this.widgets, this.spacing = 12});

  final List<DashboardWidgetSpec> widgets;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final spec in widgets)
              SizedBox(
                width: _tileWidth(maxWidth, spec.width),
                child: _buildWidget(spec),
              ),
          ],
        );
      },
    );
  }

  /// Width that lets `n` equal tiles plus their `n-1` gaps total exactly
  /// [maxWidth]: full → whole row, half → 2 per row, third → 3 per row.
  double _tileWidth(double maxWidth, DashboardWidth width) {
    final columns = switch (width) {
      DashboardWidth.full => 1,
      DashboardWidth.half => 2,
      DashboardWidth.third => 3,
    };
    if (columns == 1) return maxWidth;
    return (maxWidth - spacing * (columns - 1)) / columns;
  }

  Widget _buildWidget(DashboardWidgetSpec spec) {
    return switch (spec) {
      StatWidgetSpec() => StatWidget(spec: spec),
      TransactionListWidgetSpec() => TransactionListWidget(spec: spec),
      BalanceCardWidgetSpec() => BalanceCardWidget(spec: spec),
    };
  }
}
