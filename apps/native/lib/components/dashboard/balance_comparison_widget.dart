import 'package:app/components/dashboard/dashboard_cell.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/data/data.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/money.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Renders a [BalanceComparisonWidgetSpec]: last month's closing balance, the
/// current one, and the difference, for a currency — or just the accounts the
/// card is scoped to. Both figures come from
/// [AccountRepository.watchBalanceForCurrency], so they follow writes and sync
/// like the balance card: last month's read at the local midnight that starts
/// this month (an exclusive bound, so the previous month's last day counts
/// whole), the current one as of now.
class BalanceComparisonWidget extends StatelessWidget {
  const BalanceComparisonWidget({super.key, required this.spec});

  final BalanceComparisonWidgetSpec spec;

  @override
  Widget build(BuildContext context) {
    final repos = context.read<AppRepositories>();
    final monthClose = monthCloseAsOfMs(DateTime.now());

    return StreamBuilder<BigInt>(
      stream: repos.accounts.watchBalanceForCurrency(
        spec.currency,
        accountIds: spec.accountIds,
        asOfMs: monthClose,
      ),
      builder: (context, lastMonth) => StreamBuilder<BigInt>(
        stream: repos.accounts.watchBalanceForCurrency(
          spec.currency,
          accountIds: spec.accountIds,
        ),
        builder: (context, current) {
          final previous = lastMonth.data;
          final now = current.data;
          final difference = previous == null || now == null
              ? null
              : now - previous;
          final failed = lastMonth.hasError || current.hasError;
          return DashboardCell(
            title: context.l10n.dashboardTitle(spec.title),
            icon: Icons.compare_arrows_rounded,
            minHeight: 160,
            backgroundColor: spec.background.resolve(
              difference == null ? null : difference.toDouble() / 100,
            ),
            child: failed
                ? Text(
                    context.l10n.error,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                : Column(
                    children: [
                      _ComparisonRow(
                        label: context.l10n.dashboardLastMonthBalance,
                        cents: previous,
                        currency: spec.currency,
                      ),
                      _ComparisonRow(
                        label: context.l10n.dashboardCurrentBalance,
                        cents: now,
                        currency: spec.currency,
                        divided: true,
                      ),
                      _ComparisonRow(
                        label: context.l10n.dashboardBalanceDifference,
                        cents: difference,
                        currency: spec.currency,
                        divided: true,
                        signed: true,
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.label,
    required this.cents,
    required this.currency,
    this.divided = false,
    this.signed = false,
  });

  final String label;

  /// Null while loading.
  final BigInt? cents;
  final String currency;
  final bool divided;

  /// The difference row: a gain reads green with a `+`, like a positive
  /// amount in a transaction row.
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = cents;
    final positive = signed && value != null && value > BigInt.zero;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided
            ? Border(top: BorderSide(color: theme.colorScheme.outlineVariant))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (value == null)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                _format(value, positive, context.localeName),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: positive
                      ? Colors.green.shade600
                      : theme.colorScheme.onSurface,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The balance card's format (`ARS 1.234,00`), with a `+` on a gain.
  String _format(BigInt cents, bool positive, String locale) {
    final sign = cents < BigInt.zero
        ? '-'
        : positive
        ? '+'
        : '';
    return '$sign$currency '
        '${formatCentsUnsigned(cents.abs().toInt(), locale: locale)}';
  }
}
