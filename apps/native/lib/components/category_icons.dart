import 'package:flutter/material.dart';

/// Icon catalog for categories. The backend stores the icon as a *name* (a
/// stable string in `categories.icon`), while the UI renders an [IconData].
/// This map is the single source of truth for that name ↔ glyph mapping; keep
/// names stable so already-stored categories keep their icon across releases.
const Map<String, IconData> categoryIconsByName = {
  'category': Icons.category_rounded,
  'receipt': Icons.receipt_long_rounded,
  'shopping_bag': Icons.shopping_bag_rounded,
  'shopping_cart': Icons.shopping_cart_rounded,
  'savings': Icons.savings_rounded,
  'health': Icons.favorite_rounded,
  'education': Icons.school_rounded,
  'restaurant': Icons.restaurant_rounded,
  'transport': Icons.directions_bus_rounded,
  'home': Icons.home_rounded,
  'celebration': Icons.celebration_rounded,
  'fitness': Icons.fitness_center_rounded,
  'pets': Icons.pets_rounded,
  'help': Icons.help_outline_rounded,
};

/// Name stored when a category has no icon (or an unknown one).
const String categoryDefaultIconName = 'category';

/// Default glyph, used as a fallback when the stored name is null/unknown.
const IconData categoryDefaultIcon = Icons.category_rounded;

/// Glyphs the icon picker renders, in catalog order.
final List<IconData> categoryIconOptions = categoryIconsByName.values.toList();

/// Resolves a stored icon name to its glyph, falling back to the default.
IconData categoryIconFromName(String? name) =>
    categoryIconsByName[name] ?? categoryDefaultIcon;

/// Resolves a glyph back to its stable storage name, falling back to the
/// default name when the glyph is not in the catalog.
String categoryIconName(IconData icon) {
  for (final entry in categoryIconsByName.entries) {
    if (entry.value == icon) return entry.key;
  }
  return categoryDefaultIconName;
}
