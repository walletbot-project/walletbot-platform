import 'package:app/components/color_utils.dart';
import 'package:flutter/material.dart';

enum DashboardBackgroundMode {
  none('none'),
  fixed('fixed'),
  value('value');

  const DashboardBackgroundMode(this.wire);

  final String wire;

  static DashboardBackgroundMode fromWire(Object? wire) {
    for (final mode in values) {
      if (mode.wire == wire) return mode;
    }
    return none;
  }
}

class DashboardBackgroundStyle {
  const DashboardBackgroundStyle({
    this.mode = DashboardBackgroundMode.none,
    this.fixedColor,
    this.value,
  });

  final DashboardBackgroundMode mode;
  final Color? fixedColor;
  final DashboardValueBackground? value;

  static const none = DashboardBackgroundStyle();

  static DashboardBackgroundStyle fromJson(Object? raw) {
    if (raw is! Map) return none;
    final mode = DashboardBackgroundMode.fromWire(raw['mode']);
    return DashboardBackgroundStyle(
      mode: mode,
      fixedColor: _colorFrom(raw['fixedColor']),
      value: DashboardValueBackground.fromJson(raw['value']),
    );
  }

  Map<String, Object?>? toJson() {
    return switch (mode) {
      DashboardBackgroundMode.none => null,
      DashboardBackgroundMode.fixed => {
        'mode': mode.wire,
        'fixedColor': colorToHex(
          fixedColor ?? dashboardBackgroundPalette.first,
        ),
      },
      DashboardBackgroundMode.value => {
        'mode': mode.wire,
        'value': (value ?? DashboardValueBackground.defaults).toJson(),
      },
    };
  }

  Color? resolve([double? numericValue]) {
    return switch (mode) {
      DashboardBackgroundMode.none => null,
      DashboardBackgroundMode.fixed =>
        fixedColor ?? dashboardBackgroundPalette.first,
      DashboardBackgroundMode.value =>
        numericValue == null
            ? null
            : (value ?? DashboardValueBackground.defaults).resolve(
                numericValue,
              ),
    };
  }
}

class DashboardValueBackground {
  const DashboardValueBackground({
    required this.low,
    required this.high,
    required this.lowColor,
    required this.betweenColor,
    required this.highColor,
  });

  final double low;
  final double high;
  final Color lowColor;
  final Color betweenColor;
  final Color highColor;

  static const defaults = DashboardValueBackground(
    low: 0,
    high: 10000,
    lowColor: Color(0xFFFFCBCB),
    betweenColor: Color(0xFFFFE588),
    highColor: Color(0xFFC8F2D8),
  );

  static DashboardValueBackground? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return DashboardValueBackground(
      low: _doubleFrom(raw['low']) ?? defaults.low,
      high: _doubleFrom(raw['high']) ?? defaults.high,
      lowColor: _colorFrom(raw['lowColor']) ?? defaults.lowColor,
      betweenColor: _colorFrom(raw['betweenColor']) ?? defaults.betweenColor,
      highColor: _colorFrom(raw['highColor']) ?? defaults.highColor,
    );
  }

  Map<String, Object?> toJson() => {
    'low': low,
    'high': high,
    'lowColor': colorToHex(lowColor),
    'betweenColor': colorToHex(betweenColor),
    'highColor': colorToHex(highColor),
  };

  Color resolve(double value) {
    final lower = low <= high ? low : high;
    final upper = low <= high ? high : low;
    if (value < lower) return lowColor;
    if (value > upper) return highColor;
    return betweenColor;
  }
}

const dashboardBackgroundPalette = <Color>[
  Color(0xFFC8F2D8),
  Color(0xFFBDEFE9),
  Color(0xFFC7E5FF),
  Color(0xFFD7E0FF),
  Color(0xFFE6D3FF),
  Color(0xFFFFD0E0),
  Color(0xFFFFCBCB),
  Color(0xFFFFE588),
  Color(0xFFFFD1A8),
  Color(0xFFF3E2BF),
  Color(0xFFDCE4E2),
  Color(0xFFD5E1E7),
];

Color? _colorFrom(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return colorFromHex(raw);
}

double? _doubleFrom(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.replaceAll(',', '.'));
  return null;
}
