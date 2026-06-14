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

    return StreamBuilder<BigInt>(
      stream: repos.accounts.watchBalanceForCurrency(spec.currency),
      builder: (context, snapshot) {
        final cents = snapshot.data;
        return DashboardCell(
          title: spec.title,
          icon: Icons.account_balance_wallet_outlined,
          minHeight: 128,
          trailing: _CurrencyPill(currency: spec.currency),
          backgroundColor: spec.background.resolve(
            cents == null ? null : cents.toDouble() / 100,
          ),
          child: _BalanceValueText(
            snapshot: snapshot,
            text: cents == null ? '—' : _formatBalance(cents, spec.currency),
          ),
        );
      },
    );
  }

  String _formatBalance(BigInt cents, String currency) {
    final sign = cents < BigInt.zero ? '-' : '';
    return '$sign$currency ${formatCentsUnsigned(cents.abs().toInt())}';
  }
}

class _BalanceValueText extends StatelessWidget {
  const _BalanceValueText({required this.snapshot, required this.text});

  final AsyncSnapshot<BigInt> snapshot;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (snapshot.hasError) {
      return Text(
        'Error',
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
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onSurface,
        ),
        maxLines: 1,
      ),
    );
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
