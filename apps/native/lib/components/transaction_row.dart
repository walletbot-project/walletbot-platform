import 'package:app/shared/money.dart';
import 'package:flutter/material.dart';

class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.title,
    required this.amountCents,
    required this.dateCheck,
    this.description,
    this.currency,
    this.currencySymbol = '\$',
    this.onTap,
    this.contained = true,
  });

  final String title;

  /// Signed amount in cents. Positive values render in green with a `+` prefix,
  /// negative values render with a `-` prefix in the default text color.
  final int amountCents;

  /// `true` when the transaction date is confirmed (renders a green check),
  /// `false` when the date is estimated (renders an amber help icon).
  final bool dateCheck;

  final String? description;
  final String? currency;
  final String currencySymbol;
  final VoidCallback? onTap;
  final bool contained;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPositive = amountCents > 0;
    final amountColor = isPositive
        ? Colors.green.shade600
        : theme.colorScheme.onSurface;

    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: contained ? 16 : 0,
        vertical: contained ? 14 : 11,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _DateCheckIcon(dateConfirmed: dateCheck),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (description != null && description!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            currency == null
                ? _formatSignedAmount(amountCents, currencySymbol)
                : formatMoney(amountCents, currency!),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: amountColor,
            ),
          ),
        ],
      ),
    );

    if (!contained) {
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: content,
        ),
      );
    }

    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }
}

class _DateCheckIcon extends StatelessWidget {
  const _DateCheckIcon({required this.dateConfirmed});

  final bool dateConfirmed;

  @override
  Widget build(BuildContext context) {
    if (dateConfirmed) {
      return Icon(Icons.check_rounded, color: Colors.green.shade600, size: 22);
    }
    return Icon(
      Icons.help_outline_rounded,
      color: Colors.amber.shade700,
      size: 22,
    );
  }
}

String _formatSignedAmount(int cents, String currencySymbol) {
  final sign = cents < 0 ? '-' : (cents > 0 ? '+' : '');
  return '$sign $currencySymbol ${formatCentsUnsigned(cents.abs())}';
}
