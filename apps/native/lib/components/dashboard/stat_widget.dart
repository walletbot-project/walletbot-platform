import 'package:app/components/dashboard/dashboard_cell.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/data/data.dart';
import 'package:app/shared/money.dart';
import 'package:app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Renders a [StatWidgetSpec] as a compact card: a title and one live number,
/// reactive to writes/sync via [SummaryRepository.watchStat].
class StatWidget extends StatelessWidget {
  const StatWidget({super.key, required this.spec});

  final StatWidgetSpec spec;

  @override
  Widget build(BuildContext context) {
    final repos = context.read<AppRepositories>();

    return StreamBuilder<StatValue>(
      stream: repos.summaries.watchStat(spec.filter, spec.aggregation),
      builder: (context, snapshot) {
        final value = snapshot.data;
        return DashboardCell(
          title: context.l10n.dashboardTitle(spec.title),
          icon: _iconFor(spec.aggregation),
          minHeight: 128,
          backgroundColor: spec.background.resolve(_styleValue(value)),
          child: _StatValueText(
            snapshot: snapshot,
            text: value == null
                ? '—'
                : _formatValue(value, spec.filter.currency, context.localeName),
          ),
        );
      },
    );
  }

  IconData _iconFor(StatAggregation aggregation) {
    return switch (aggregation) {
      StatAggregation.count => Icons.format_list_numbered_rounded,
      StatAggregation.net => Icons.swap_vert_rounded,
      StatAggregation.sum => Icons.calculate_outlined,
    };
  }

  /// Counts render as a bare integer; monetary aggregations prefix the currency
  /// code and carry a sign only when net flow is negative.
  String _formatValue(StatValue value, String? currency, String locale) {
    if (value.aggregation == StatAggregation.count) {
      return '${value.count}';
    }
    final cents = value.amountCents;
    final sign = value.aggregation == StatAggregation.net && cents < BigInt.zero
        ? '-'
        : '';
    final amount = formatCentsUnsigned(cents.abs().toInt(), locale: locale);
    return currency == null ? '$sign$amount' : '$sign$currency $amount';
  }

  double? _styleValue(StatValue? value) {
    if (value == null) return null;
    if (value.aggregation == StatAggregation.count) {
      return value.count.toDouble();
    }
    return value.amountCents.toDouble() / 100;
  }
}

class _StatValueText extends StatelessWidget {
  const _StatValueText({required this.snapshot, required this.text});

  final AsyncSnapshot<StatValue> snapshot;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (snapshot.hasError) {
      return Text(
        context.l10n.error,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onSurface,
        ),
        maxLines: 1,
      ),
    );
  }
}
