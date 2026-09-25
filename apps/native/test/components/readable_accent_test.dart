import 'package:app/components/color_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readableAccent', () {
    test('returns every stored accent unchanged in light mode', () {
      for (final color in colorOptions) {
        expect(readableAccent(color, Brightness.light), color);
      }
    });

    test('keeps the hue and softens the accent in dark mode', () {
      for (final color in colorOptions) {
        final original = HSLColor.fromColor(color);
        final adapted = HSLColor.fromColor(
          readableAccent(color, Brightness.dark),
        );
        expect(adapted.lightness, closeTo(0.72, 0.01));
        expect(adapted.saturation, lessThanOrEqualTo(0.66));
        if (original.saturation > 0.05) {
          expect(adapted.hue, closeTo(original.hue, 2));
        }
      }
    });

    test('is idempotent, so adapting twice paints the same color', () {
      for (final color in colorOptions) {
        final once = readableAccent(color, Brightness.dark);
        final twice = readableAccent(once, Brightness.dark);
        expect(colorToHex(twice), colorToHex(once));
      }
    });
  });
}
