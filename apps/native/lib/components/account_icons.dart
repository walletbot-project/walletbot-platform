import 'package:flutter/material.dart';

/// Icon catalog for accounts. The backend stores the icon as a *name* (a stable
/// string in `accounts.icon`), while the UI renders an [IconData]. This map is
/// the single source of truth for that name ↔ glyph mapping; keep names stable
/// so already-stored accounts keep their icon across releases (and platforms).
const Map<String, IconData> accountIconsByName = {
  'wallet': Icons.account_balance_wallet_rounded,
  'bank': Icons.account_balance_rounded,
  'savings': Icons.savings_rounded,
  'cash': Icons.payments_rounded,
  'card': Icons.credit_card_rounded,
  'travel': Icons.flight_takeoff_rounded,
  'investment': Icons.trending_up_rounded,
  'money': Icons.attach_money_rounded,
  'exchange': Icons.currency_exchange_rounded,
  'real_estate': Icons.real_estate_agent_rounded,
  'wallet_alt': Icons.wallet_rounded,
};

/// Name stored when an account has no icon (or an unknown one).
const String accountDefaultIconName = 'wallet';

/// Default glyph, used as a fallback when the stored name is null/unknown.
const IconData accountDefaultIcon = Icons.account_balance_wallet_rounded;

/// Glyphs the icon picker renders, in catalog order.
final List<IconData> accountIconOptions = accountIconsByName.values.toList();

/// Resolves a stored icon name to its glyph, falling back to the default.
IconData accountIconFromName(String? name) =>
    accountIconsByName[name] ?? accountDefaultIcon;

/// Resolves a glyph back to its stable storage name, falling back to the
/// default name when the glyph is not in the catalog.
String accountIconName(IconData icon) {
  for (final entry in accountIconsByName.entries) {
    if (entry.value == icon) return entry.key;
  }
  return accountDefaultIconName;
}
