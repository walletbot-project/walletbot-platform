import 'package:app/shared/money.dart';
import 'package:flutter/material.dart';

class TransactionRowEmoji extends StatelessWidget {
  const TransactionRowEmoji({
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
  final List<TransactionRowEmojiVisualIdentity> visualIdentities;
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
    TransactionRowEmojiVisualIdentity? accountIdentity;
    TransactionRowEmojiVisualIdentity? timeIdentity;
    final detailIdentities = <TransactionRowEmojiVisualIdentity>[];
    for (final identity in visualIdentities) {
      if (identity.type == TransactionRowEmojiVisualIdentityType.account &&
          accountIdentity == null) {
        accountIdentity = identity;
      } else if (identity.type == TransactionRowEmojiVisualIdentityType.time &&
          timeIdentity == null) {
        timeIdentity = identity;
      } else {
        detailIdentities.add(identity);
      }
    }

    final rowContent = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: contained ? 16 : 0,
        vertical: contained ? 14 : 11,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (accountIdentity == null)
            const SizedBox(width: 32, height: 32)
          else
            _IdentityIcon(identity: accountIdentity, size: 32, iconSize: 19),
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
                if (detailIdentities.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final identity in detailIdentities)
                        _IdentityIcon(identity: identity),
                    ],
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
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        rowContent,
        Positioned(
          top: contained ? 7 : 0,
          right: contained ? 8 : 0,
          child: IgnorePointer(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!dateCheck) _DateCheckIcon(size: 14),
                if (timeIdentity != null) ...[
                  if (!dateCheck) const SizedBox(width: 4),
                  _IdentityIcon(identity: timeIdentity, size: 16, iconSize: 13),
                ],
              ],
            ),
          ),
        ),
      ],
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

class TransactionRowEmojiVisualIdentity {
  const TransactionRowEmojiVisualIdentity({
    required this.type,
    required this.label,
    required this.icon,
    required this.color,
  });

  final TransactionRowEmojiVisualIdentityType type;
  final String label;
  final IconData icon;
  final Color color;
}

enum TransactionRowEmojiVisualIdentityType { account, category, time }

class _IdentityIcon extends StatelessWidget {
  const _IdentityIcon({
    required this.identity,
    this.size = 24,
    this.iconSize = 15,
  });

  final TransactionRowEmojiVisualIdentity identity;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (identity.type == TransactionRowEmojiVisualIdentityType.time) {
      return Tooltip(
        message: identity.label,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: Icon(identity.icon, size: iconSize + 2)),
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
