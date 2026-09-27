import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Accent used by tags that have no stored color.
const Color tagDefaultColor = Colors.greenAccent;

/// Accent used by accounts that have no stored color.
const Color accountDefaultColor = Color(0xFF3B82F6);

/// Accent used by categories that have no stored color.
const Color categoryDefaultColor = Color(0xFF6366F1);

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
  Color(0xFF06B6D4),
  Color(0xFF84CC16),
  Color(0xFFF43F5E),
  Color(0xFF0EA5E9),
  Color(0xFFD946EF),
  Color(0xFFF97316),
];

/// Derives a soft pastel tint of [color]: keeps the hue but drops the
/// saturation and lifts the lightness, so an accent from [colorOptions] reads as
/// a gentle wash of itself. Shared by every surface that wants a pastel fill
/// (e.g. dashboard widget backgrounds) so they stay consistent with the entity
/// accents tags, categories and accounts pick from.
Color pastelize(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withSaturation((hsl.saturation * 0.6).clamp(0.0, 1.0))
      .withLightness(
        (hsl.lightness + (1 - hsl.lightness) * 0.7).clamp(0.0, 1.0),
      )
      .toColor();
}

/// Adapts a stored [pastelize]d widget background so its content stays legible
/// in both themes. Widget backgrounds are persisted as light pastels, which
/// work under dark-on-light text in light mode but leave the theme's
/// light-on-dark text unreadable in dark mode. In light themes the pastel is
/// returned as-is; in dark themes it is rebuilt as a deep tint of the same hue
/// (fixed low lightness) so the same content reads against it.
Color readableWidgetBackground(Color background, Brightness brightness) {
  if (brightness == Brightness.light) return background;
  final hsl = HSLColor.fromColor(background);
  return hsl
      .withSaturation(hsl.saturation.clamp(0.3, 0.6))
      .withLightness(0.24)
      .toColor();
}

/// Adapts a stored account or category accent (any [colorOptions] pick) to
/// how it is painted in the current theme. Tags are not adapted: they keep
/// their raw color in both themes (see `tagChipStyle`). Accents are persisted as
/// saturated colors, which suit light surfaces but glare on dark ones. In light
/// themes the accent is returned as-is; in dark themes it is lifted and
/// softened in OKLCH, a perceptual space: every accent gains the same
/// lightness ([_darkAccentLift]) and keeps the same share of its chroma
/// ([_darkAccentChroma]), with the hue untouched. Shifting them all alike keeps
/// the lightness and intensity gaps between palette colors, so the dark palette
/// stays as varied as the light one. The stored value never changes — only
/// what gets painted, the same way [readableWidgetBackground] adapts widget
/// backgrounds. Not idempotent: adapt the stored color exactly once. Mirrors
/// `readableAccent` in apps/web/src/lib/entity-colors.ts.
Color readableAccent(Color accent, Brightness brightness) {
  if (brightness == Brightness.light) return accent;
  final (l, a, b) = _toOklab(accent);
  final hue = math.atan2(b, a);
  final lightness = math.min(l + _darkAccentLift, 1.0);
  var chroma = math.sqrt(a * a + b * b) * _darkAccentChroma;
  var rgb = _fromOklab(
    lightness,
    chroma * math.cos(hue),
    chroma * math.sin(hue),
  );
  // Out-of-gamut tones lose chroma until they fit in sRGB, keeping the hue.
  for (var i = 0; i < 60 && !_inGamut(rgb); i++) {
    chroma *= 0.97;
    rgb = _fromOklab(lightness, chroma * math.cos(hue), chroma * math.sin(hue));
  }
  int channel(double linear) =>
      (_encodeSrgb(linear.clamp(0.0, 1.0)) * 255).round();
  return Color.fromARGB(
    (accent.a * 255).round(),
    channel(rgb.$1),
    channel(rgb.$2),
    channel(rgb.$3),
  );
}

/// OKLCH lightness every dark-mode accent gains (see [readableAccent]).
const double _darkAccentLift = 0.06;

/// Share of its OKLCH chroma a dark-mode accent keeps (see [readableAccent]).
const double _darkAccentChroma = 0.8;

double _decodeSrgb(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _encodeSrgb(double c) => c <= 0.0031308
    ? 12.92 * c
    : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

/// [color] in OKLab as (L, a, b), from its gamma-encoded sRGB channels.
(double, double, double) _toOklab(Color color) {
  final r = _decodeSrgb(color.r);
  final g = _decodeSrgb(color.g);
  final b = _decodeSrgb(color.b);
  final l = math
      .pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1 / 3)
      .toDouble();
  final m = math
      .pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1 / 3)
      .toDouble();
  final s = math
      .pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1 / 3)
      .toDouble();
  return (
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  );
}

/// OKLab (L, a, b) back to linear sRGB; channels may fall outside 0–1.
(double, double, double) _fromOklab(double lightness, double a, double b) {
  final l = math.pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3);
  final m = math.pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3);
  final s = math.pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3);
  return (
    (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s).toDouble(),
    (-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s).toDouble(),
    (-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s).toDouble(),
  );
}

bool _inGamut((double, double, double) rgb) {
  const tolerance = 1e-4;
  bool fits(double c) => c >= -tolerance && c <= 1 + tolerance;
  return fits(rgb.$1) && fits(rgb.$2) && fits(rgb.$3);
}

/// Picks a legible foreground (near-black or near-white) for text/icons drawn
/// on top of [background], choosing whichever yields the higher contrast ratio.
/// Used for tag chips whose fill is the tag's own identity color: the fill must
/// stay as the user picked it, so only the label adapts to remain readable in
/// both themes and for any color.
Color foregroundOn(Color background) {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  const black = Color(0xFF000000);
  const white = Color(0xFFFFFFFF);
  return contrast(background, white) >= contrast(background, black)
      ? white
      : black;
}

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
