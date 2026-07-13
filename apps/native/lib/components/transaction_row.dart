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
    this.visualIdentities = const [],
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
  final List<TransactionRowVisualIdentity> visualIdentities;
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
    TransactionRowVisualIdentity? timeIdentity;
    final detailIdentities = <TransactionRowVisualIdentity>[];
    for (final identity in visualIdentities) {
      if (identity.type == TransactionRowVisualIdentityType.time &&
          timeIdentity == null) {
        timeIdentity = identity;
      } else {
        detailIdentities.add(identity);
      }
    }
    final showAttention = !dateCheck || (timeIdentity?.attention ?? false);

    final rowContent = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: contained ? 16 : 0,
        vertical: contained ? 14 : 11,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          if (detailIdentities.isNotEmpty ||
              timeIdentity != null ||
              !dateCheck) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final identity in detailIdentities)
                        _IdentityIcon(identity: identity),
                    ],
                  ),
                ),
                if (showAttention || timeIdentity != null) ...[
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showAttention) const _DateCheckIcon(size: 15),
                      if (showAttention && timeIdentity != null)
                        const SizedBox(width: 4),
                      if (timeIdentity != null)
                        _IdentityIcon(
                          identity: timeIdentity,
                          size: 18,
                          iconSize: 14,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    if (!contained) {
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: rowContent,
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
        child: rowContent,
      ),
    );
  }
}

class TransactionRowVisualIdentity {
  const TransactionRowVisualIdentity({
    required this.type,
    required this.label,
    required this.icon,
    required this.color,
    this.attention = false,
  });

  final TransactionRowVisualIdentityType type;
  final String label;
  final IconData icon;
  final Color color;
  final bool attention;
}

enum TransactionRowVisualIdentityType { account, category, time }

class _IdentityIcon extends StatelessWidget {
  const _IdentityIcon({
    required this.identity,
    this.size = 24,
    this.iconSize = 15,
  });

  final TransactionRowVisualIdentity identity;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (identity.type == TransactionRowVisualIdentityType.time) {
      final color = identity.attention
          ? Colors.amber.shade700
          : Theme.of(context).colorScheme.onSurfaceVariant;
      return Tooltip(
        message: identity.label,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              identity.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return Tooltip(
      message: identity.label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: identity.color.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(identity.icon, size: iconSize, color: identity.color),
      ),
    );
  }
}

class _DateCheckIcon extends StatelessWidget {
  const _DateCheckIcon({this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.help_outline_rounded,
      color: Colors.amber.shade700,
      size: size,
    );
  }
}

String _formatSignedAmount(int cents, String currencySymbol) {
  final sign = cents < 0 ? '-' : (cents > 0 ? '+' : '');
  return '$sign $currencySymbol ${formatCentsUnsigned(cents.abs())}';
}
