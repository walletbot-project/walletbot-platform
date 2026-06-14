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
            StreamBuilder<BigInt>(
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
                // Scale long balances down to the tile width instead of
                // truncating them.
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text,
                    style: theme.textTheme.headlineSmall?.copyWith(
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

  String _formatBalance(BigInt cents, String currency) {
    final sign = cents < BigInt.zero ? '-' : '';
    return '$sign$currency ${formatCentsUnsigned(cents.abs().toInt())}';
  }
}
