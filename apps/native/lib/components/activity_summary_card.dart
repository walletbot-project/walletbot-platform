import 'package:flutter/material.dart';

class ActivitySummaryCard extends StatelessWidget {
  const ActivitySummaryCard({
    super.key,
    required this.incomeCents,
    required this.expensesCents,
    required this.balanceCents,
    this.currencySymbol = '\$',
  });

  /// Total income for the period, in cents. Always rendered as a positive value.
  final int incomeCents;

  /// Total expenses for the period, in cents. Always rendered as a positive value.
  final int expensesCents;

  /// Net balance for the period, in cents. May be negative.
  final int balanceCents;

  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _SummaryColumn(
              label: 'Ingresos',
              value: _formatAmount(incomeCents.abs(), currencySymbol),
              valueColor: Colors.green.shade600,
            ),
          ),
          Expanded(
            child: _SummaryColumn(
              label: 'Gastos',
              value: _formatAmount(expensesCents.abs(), currencySymbol),
              valueColor: Colors.red.shade600,
            ),
          ),
          Expanded(
            child: _SummaryColumn(
              label: 'Balance',
              value: _formatAmount(balanceCents, currencySymbol),
              valueColor: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryColumn extends StatelessWidget {
  const _SummaryColumn({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

String _formatAmount(int cents, String currencySymbol) {
  final whole = (cents / 100).round();
  final digits = whole.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(digits[i]);
  }
  return '$currencySymbol$buffer';
}
