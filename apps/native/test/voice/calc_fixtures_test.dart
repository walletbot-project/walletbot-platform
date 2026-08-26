// The Dart half of the cross-language calculator parity suite. The same
// fixture table runs against the TS originals in
// packages/shared/test/calc-fixtures.test.ts — a behavioural change on one
// side fails the other side's run until both are updated together.

import 'dart:convert';
import 'dart:io';

import 'package:app/voice/tool_calc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // flutter test runs with cwd = apps/native.
  final fixtures =
      jsonDecode(
            File(
              '../../packages/shared/src/tools/calc-fixtures.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  final nowComponents = (fixtures['now'] as Map).cast<String, Object?>();
  final now = DateTime(
    nowComponents['year'] as int,
    nowComponents['month'] as int,
    nowComponents['day'] as int,
    nowComponents['hour'] as int,
    nowComponents['minute'] as int,
    nowComponents['second'] as int,
    nowComponents['millisecond'] as int,
  );

  group('runCalculate fixtures', () {
    for (final raw in fixtures['calculate'] as List) {
      final c = (raw as Map).cast<String, Object?>();
      final steps = c['steps'] as List;
      final label = steps.isEmpty
          ? '(empty)'
          : steps
                .map((s) => (s as Map).cast<String, Object?>()['expression'])
                .join(' ; ');
      test(label, () {
        if (c['throws'] == true) {
          expect(() => runCalculate(steps), throwsA(anything));
          return;
        }
        final expected = (c['values'] as List).cast<num>();
        final results = runCalculate(steps);
        // Both engines compute in IEEE 754 doubles — results are exact.
        expect(
          results.map((r) => r['value']).toList(),
          expected.map((v) => v.toDouble()).toList(),
        );
      });
    }
  });

  group('runCalculateDate fixtures', () {
    for (final raw in fixtures['calculateDate'] as List) {
      final c = (raw as Map).cast<String, Object?>();
      final args = (c['args'] as Map).cast<String, Object?>();
      test(jsonEncode(args), () {
        if (c['throws'] == true) {
          expect(() => runCalculateDate(args, now: now), throwsA(anything));
          return;
        }
        final expected = (c['expect'] as Map).cast<String, Object?>();
        expect(runCalculateDate(args, now: now), expected);
      });
    }
  });
}
