import 'package:flutter/material.dart';

/// Icon catalog for categories. Mirrors the shape of `color_utils`: a default
/// plus a curated option list the icon picker renders. Prototype-only visuals
/// (the backend has no icon field for categories).
const IconData categoryDefaultIcon = Icons.category_rounded;

const categoryIconOptions = <IconData>[
  categoryDefaultIcon,
  Icons.receipt_long_rounded,
  Icons.shopping_bag_rounded,
  Icons.shopping_cart_rounded,
  Icons.savings_rounded,
  Icons.favorite_rounded,
  Icons.school_rounded,
  Icons.restaurant_rounded,
  Icons.directions_bus_rounded,
  Icons.home_rounded,
  Icons.celebration_rounded,
  Icons.fitness_center_rounded,
  Icons.pets_rounded,
  Icons.help_outline_rounded,
];
