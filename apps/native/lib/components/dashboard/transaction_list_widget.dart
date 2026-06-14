import 'package:app/components/dashboard/dashboard_cell.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/components/transaction_row.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/shared/money.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Renders a [TransactionListWidgetSpec] as a card with a title and the most
/// recent matching rows, reactive to writes/sync via
/// [TransactionRepository.watch]. Handles loading, error, and empty states.
class TransactionListWidget extends StatelessWidget {
  const TransactionListWidget({super.key, required this.spec});

  final TransactionListWidgetSpec spec;

  @override
  Widget build(BuildContext context) {
    final repos = context.read<AppRepositories>();
    final theme = Theme.of(context);

    return DashboardCell(
      title: spec.title,
      icon: Icons.receipt_long_outlined,
      minHeight: 160,
      child: StreamBuilder<List<Transaction>>(
        stream: repos.transactions.watch(spec.filter, limit: spec.limit),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
              'No se pudieron cargar los movimientos.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final items = snapshot.data ?? const <Transaction>[];
          if (items.isEmpty) {
            return Text(
              'No hay movimientos todavía.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            );
          }

          return Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                TransactionRow(
                  title: items[i].name,
                  amountCents: signedDisplayCents(
                    items[i].type,
                    items[i].amount,
                  ),
                  dateCheck: items[i].dateConfirmed,
                  contained: false,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
