import 'dart:math' as math;

import 'package:app/components/color_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Expected dark-mode paint for every palette accent. The same table backs
/// apps/web/src/lib/entity-colors.test.ts, so both platforms paint the same
/// hex for the same stored color.
const _darkPalette = <String, String>{
  '#69F0AE': '#9AFFC9',
  '#26A69A': '#5EB5AB',
  '#42A5F5': '#6EB8F8',
  '#FFCA28': '#FEE39F',
  '#FF7043': '#FE9574',
  '#AB47BC': '#B567C3',
  '#78909C': '#8EA2AB',
  '#3B82F6': '#5F98F5',
  '#14B8A6': '#61C7B7',
  '#F59E0B': '#FDB760',
  '#EF4444': '#F36D66',
  '#6366F1': '#7780EF',
  '#8B5CF6': '#997BF4',
  '#10B981': '#5FC799',
  '#EC4899': '#F270AA',
  '#06B6D4': '#60C6DE',
  '#84CC16': '#A1DC63',
  '#F43F5E': '#F86B7A',
  '#0EA5E9': '#5AB7EE',
  '#D946EF': '#E172F2',
  '#F97316': '#FE9258',
};

void main() {
  group('readableAccent', () {
    test('returns every stored accent unchanged in light mode', () {
      for (final color in colorOptions) {
        expect(readableAccent(color, Brightness.light), color);
      }
    });

    test('paints every palette accent as the shared dark table', () {
      expect(_darkPalette.length, colorOptions.length);
      for (final color in colorOptions) {
        final hex = colorToHex(color);
        expect(
          colorToHex(readableAccent(color, Brightness.dark)),
          _darkPalette[hex],
          reason: hex,
        );
      }
    });

    test('keeps the dark palette as varied as the light one', () {
      // Brightness spread (max - min relative luminance) survives the shift.
      double spread(Iterable<Color> colors) {
        final values = colors.map((c) => c.computeLuminance()).toList();
        return values.reduce(math.max) - values.reduce(math.min);
      }

      final dark = colorOptions.map((c) => readableAccent(c, Brightness.dark));
      expect(spread(dark), greaterThan(spread(colorOptions) * 0.8));
    });

    test('stays in range for colors outside the palette', () {
      expect(
        colorToHex(readableAccent(Colors.white, Brightness.dark)),
        '#FFFFFF',
      );
      expect(
        colorToHex(readableAccent(Colors.black, Brightness.dark)),
        '#010101',
      );
    });
  });
}
