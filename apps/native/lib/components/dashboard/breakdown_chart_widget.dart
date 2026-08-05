import 'package:app/components/color_utils.dart';
import 'package:app/components/dashboard/dashboard_cell.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/data/data.dart';
import 'package:app/shared/money.dart';
import 'package:app/l10n/l10n.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Renders a [ChartWidgetSpec] as a card with a title and a pie / bar / line
/// chart of the filtered transactions bucketed by group, reactive to
/// writes/sync via [SummaryRepository.watchBreakdown]. Handles loading, error,
/// and empty states. Slices with a stored color (accounts) use it; the rest
/// fall back to a fixed palette.
class BreakdownChartWidget extends StatelessWidget {
  const BreakdownChartWidget({super.key, required this.spec});

  final ChartWidgetSpec spec;

  static const _palette = <Color>[
    Color(0xFF42A5F5),
    Color(0xFF26A69A),
    Color(0xFFFFCA28),
    Color(0xFFFF7043),
    Color(0xFFAB47BC),
    Color(0xFF78909C),
    Color(0xFFEC407A),
    Color(0xFF9CCC65),
  ];

  Color _colorFor(BreakdownSlice slice, int index) => slice.colorHex != null
      ? colorFromHex(slice.colorHex)
      : _palette[index % _palette.length];

  @override
  Widget build(BuildContext context) {
    final repos = context.read<AppRepositories>();

    return StreamBuilder<List<BreakdownSlice>>(
      stream: repos.summaries.watchBreakdown(
        spec.filter,
        spec.groupBy,
        missingCategoryLabel: context.l10n.uncategorized,
        missingAccountLabel: context.l10n.unknownAccount,
        monthLabel: (date) => formatMonthYear(date, context.localeName),
      ),
      builder: (context, snapshot) {
        final slices = (snapshot.data ?? const <BreakdownSlice>[])
            .where((s) => s.totalCents > BigInt.zero)
            .toList();
        final total = slices.fold(BigInt.zero, (sum, s) => sum + s.totalCents);
        return DashboardCell(
          title: context.l10n.dashboardTitle(spec.title),
          icon: _iconFor(spec.chartKind),
          minHeight: 280,
          backgroundColor: spec.background.resolve(
            snapshot.hasData ? total.toDouble() / 100 : null,
          ),
          child: _ChartContent(
            snapshot: snapshot,
            slices: slices,
            chartKind: spec.chartKind,
            pie: _pie,
            bar: _bar,
            line: _line,
          ),
        );
      },
    );
  }

  IconData _iconFor(BreakdownChartKind chartKind) {
    return switch (chartKind) {
      BreakdownChartKind.pie => Icons.donut_large_rounded,
      BreakdownChartKind.bar => Icons.bar_chart_rounded,
      BreakdownChartKind.line => Icons.show_chart_rounded,
    };
  }

  // ---- Pie ----------------------------------------------------------------

  Widget _pie(BuildContext context, List<BreakdownSlice> slices) {
    final total = slices.fold(BigInt.zero, (sum, s) => sum + s.totalCents);
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 36,
              sections: [
                for (var i = 0; i < slices.length; i++)
                  PieChartSectionData(
                    value: slices[i].totalCents.toDouble(),
                    color: _colorFor(slices[i], i),
                    radius: 56,
                    showTitle: _showsPct(slices[i].totalCents, total),
                    title: _pct(slices[i].totalCents, total),
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _legend(context, slices),
      ],
    );
  }

  /// Only label a slice that owns at least 8% of the pie — smaller slices'
  /// percentages overlap into noise, and the legend covers them anyway.
  bool _showsPct(BigInt part, BigInt total) =>
      total > BigInt.zero && part * BigInt.from(100) >= total * BigInt.from(8);

  String _pct(BigInt part, BigInt total) {
    if (total <= BigInt.zero) return '';
    final pct = (part.toDouble() / total.toDouble() * 100).round();
    return '$pct%';
  }

  Widget _legend(BuildContext context, List<BreakdownSlice> slices) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (var i = 0; i < slices.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _colorFor(slices[i], i),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${slices[i].label}  '
                '${_amount(slices[i].totalCents, context.localeName)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ---- Bar ----------------------------------------------------------------

  Widget _bar(BuildContext context, List<BreakdownSlice> slices) {
    final maxCents = slices
        .map((s) => s.totalCents)
        .reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxCents.toDouble() / 100 * 1.15,
          barTouchData: BarTouchData(enabled: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: _axisTitles(context, slices),
          barGroups: [
            for (var i = 0; i < slices.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: slices[i].totalCents.toDouble() / 100,
                    color: _colorFor(slices[i], i),
                    width: 16,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ---- Line ---------------------------------------------------------------

  Widget _line(BuildContext context, List<BreakdownSlice> slices) {
    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          lineTouchData: const LineTouchData(enabled: false),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: _axisTitles(context, slices),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < slices.length; i++)
                  FlSpot(i.toDouble(), slices[i].totalCents.toDouble() / 100),
              ],
              isCurved: true,
              color: _palette.first,
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Shared axis (bar + line) -------------------------------------------

  /// Hides the numeric left/right/top axes and labels the bottom axis with each
  /// bucket's (abbreviated) label by index. Pie charts use the legend instead.
  FlTitlesData _axisTitles(BuildContext context, List<BreakdownSlice> slices) {
    final theme = Theme.of(context);
    return FlTitlesData(
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          interval: 1,
          getTitlesWidget: (value, meta) {
            final index = value.round();
            if (index < 0 || index >= slices.length) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _short(slices[index].label),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      ),
    );
  }

  /// Trims a bucket label so adjacent axis labels don't collide.
  String _short(String label) =>
      label.length <= 6 ? label : '${label.substring(0, 6)}…';

  String _amount(BigInt cents, String locale) {
    final formatted = formatCentsUnsigned(cents.abs().toInt(), locale: locale);
    final currency = spec.filter.currency;
    return currency == null ? formatted : '$currency $formatted';
  }
}

class _ChartContent extends StatelessWidget {
  const _ChartContent({
    required this.snapshot,
    required this.slices,
    required this.chartKind,
    required this.pie,
    required this.bar,
    required this.line,
  });

  final AsyncSnapshot<List<BreakdownSlice>> snapshot;
  final List<BreakdownSlice> slices;
  final BreakdownChartKind chartKind;
  final Widget Function(BuildContext, List<BreakdownSlice>) pie;
  final Widget Function(BuildContext, List<BreakdownSlice>) bar;
  final Widget Function(BuildContext, List<BreakdownSlice>) line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (snapshot.hasError) {
      return Text(
        context.l10n.chartLoadFailed,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (slices.isEmpty) {
      return Text(
        context.l10n.chartNoData,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return switch (chartKind) {
      BreakdownChartKind.pie => pie(context, slices),
      BreakdownChartKind.bar => bar(context, slices),
      BreakdownChartKind.line => line(context, slices),
    };
  }
}
