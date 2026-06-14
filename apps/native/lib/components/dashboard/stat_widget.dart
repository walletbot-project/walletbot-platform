import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/data/data.dart';
import 'package:app/shared/money.dart';
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
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              spec.title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            StreamBuilder<StatValue>(
              stream: repos.summaries.watchStat(spec.filter, spec.aggregation),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Error',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  );
                }
                final value = snapshot.data;
                final text = value == null
                    ? '—'
                    : _formatValue(value, spec.filter.currency);
                // Scale long amounts down to the tile width instead of
                // truncating them — a third-width tile can't fit "ARS
                // 1,234.56" at full title size.
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Counts render as a bare integer; monetary aggregations prefix the currency
  /// code and carry a sign only when net flow is negative.
  String _formatValue(StatValue value, String? currency) {
    if (value.aggregation == StatAggregation.count) {
      return '${value.count}';
    }
    final cents = value.amountCents;
    final sign = value.aggregation == StatAggregation.net && cents < BigInt.zero
        ? '-'
        : '';
    final amount = formatCentsUnsigned(cents.abs().toInt());
    return currency == null ? '$sign$amount' : '$sign$currency $amount';
  }
}
