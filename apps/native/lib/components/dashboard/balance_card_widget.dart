import 'package:app/components/dashboard/dashboard_cell.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/data/data.dart';
import 'package:app/shared/money.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Renders a [BalanceCardWidgetSpec] as a card showing the live total balance
/// for a currency, reactive to writes/sync via
/// [AccountRepository.watchBalanceForCurrency].
class BalanceCardWidget extends StatelessWidget {
  const BalanceCardWidget({super.key, required this.spec});

  final BalanceCardWidgetSpec spec;

  @override
  Widget build(BuildContext context) {
    final repos = context.read<AppRepositories>();
    final theme = Theme.of(context);

    return DashboardCell(
      title: spec.title,
      icon: Icons.account_balance_wallet_outlined,
      minHeight: 128,
      trailing: _CurrencyPill(currency: spec.currency),
      child: StreamBuilder<BigInt>(
        stream: repos.accounts.watchBalanceForCurrency(spec.currency),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
              'Error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            );
          }
          final cents = snapshot.data;
          final text = cents == null
              ? '—'
              : _formatBalance(cents, spec.currency);
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 1,
            ),
          );
        },
      ),
    );
  }

  String _formatBalance(BigInt cents, String currency) {
    final sign = cents < BigInt.zero ? '-' : '';
    return '$sign$currency ${formatCentsUnsigned(cents.abs().toInt())}';
  }
}

class _CurrencyPill extends StatelessWidget {
  const _CurrencyPill({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          currency,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
