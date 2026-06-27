import 'package:app/components/grouped_card.dart';
import 'package:app/shared/money.dart';
import 'package:flutter/material.dart';

/// A single account rendered as a Material 3 expressive card-like list tile:
/// accent icon avatar, name, and a signed balance (negative uses the error
/// color). The grouped-card shape and tap behavior are injected by the caller.
class AccountListTile extends StatelessWidget {
  const AccountListTile({
    super.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.balanceCents,
    required this.currency,
    required this.borderRadius,
    this.onTap,
  });

  final String name;
  final IconData icon;
  final Color color; // visual accent
  final int balanceCents; // computed balance, can be negative
  final String currency; // ISO code: USD, ARS, EUR, GBP
  final BorderRadius borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isNegative = balanceCents < 0;

    return GroupedCard(
      borderRadius: borderRadius,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            // Leading icon tinted with the account's accent color.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                name,
                style: textTheme.bodyLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 16),
            // Balance: signed, with currency; negative balances use error color.
            Text(
              formatMoney(balanceCents, currency),
              style: textTheme.titleMedium?.copyWith(
                color: isNegative ? colors.error : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
