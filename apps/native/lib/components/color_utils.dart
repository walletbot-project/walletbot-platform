import 'package:flutter/material.dart';

/// Accent used by tags that have no stored color.
const Color tagDefaultColor = Colors.greenAccent;

/// Accent used by accounts that have no stored color.
const Color accountDefaultColor = Color(0xFF3B82F6);

/// Single swatch palette shared by every accent picker (tags, accounts, …).
/// Holds every color the app offers.
const colorOptions = <Color>[
  tagDefaultColor,
  Color(0xFF26A69A),
  Color(0xFF42A5F5),
  Color(0xFFFFCA28),
  Color(0xFFFF7043),
  Color(0xFFAB47BC),
  Color(0xFF78909C),
  accountDefaultColor,
  Color(0xFF14B8A6),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFF6366F1),
  Color(0xFF8B5CF6),
  Color(0xFF10B981),
  Color(0xFFEC4899),
];

String colorToHex(Color color) {
  final alpha = (color.a * 255).round() & 0xff;
  final red = (color.r * 255).round() & 0xff;
  final green = (color.g * 255).round() & 0xff;
  final blue = (color.b * 255).round() & 0xff;

  return '#${red.toRadixString(16).padLeft(2, '0')}'
          '${green.toRadixString(16).padLeft(2, '0')}'
          '${blue.toRadixString(16).padLeft(2, '0')}'
          '${alpha == 0xff ? '' : alpha.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}

Color colorFromHex(String? hex, {Color fallback = tagDefaultColor}) {
  if (hex == null || hex.isEmpty) return fallback;

  final cleanHex = hex.replaceFirst('#', '');
  final value = int.tryParse(cleanHex, radix: 16);
  if (value == null) return fallback;

  return switch (cleanHex.length) {
    6 => Color(0xff000000 | value),
    8 => Color(value),
    _ => fallback,
  };
}
