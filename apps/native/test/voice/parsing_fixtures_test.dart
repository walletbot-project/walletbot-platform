// The Dart half of the cross-language parsing parity suite. The same fixture
// table runs against the TS originals in
// packages/shared/test/parsing-fixtures.test.ts — a behavioural change on one
// side fails the other side's run until both are updated together.

import 'dart:convert';
import 'dart:io';

import 'package:app/database.dart';
import 'package:app/voice/tool_parsing.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _toDate(Map<String, Object?> local) => DateTime(
  local['year'] as int,
  local['month'] as int,
  local['day'] as int,
  (local['hour'] as int?) ?? 0,
  (local['minute'] as int?) ?? 0,
  (local['second'] as int?) ?? 0,
  (local['millisecond'] as int?) ?? 0,
);

TransactionTimeStatus _timeStatus(String wire) => switch (wire) {
  'confirmed' => TransactionTimeStatus.confirmed,
  'approximation' => TransactionTimeStatus.approximation,
  'none' => TransactionTimeStatus.none,
  _ => throw ArgumentError('Unknown timeStatus: $wire'),
};

void main() {
  // flutter test runs with cwd = apps/native.
  final fixtures =
      jsonDecode(
            File(
              '../../packages/shared/src/tools/parsing-fixtures.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  final now = _toDate((fixtures['now'] as Map).cast<String, Object?>());

  group('parseAmountToCents fixtures', () {
    for (final raw in fixtures['amountToCents'] as List) {
      final c = (raw as Map).cast<String, Object?>();
      test('${c['input']} → ${c['cents']}', () {
        expect(
          parseAmountToCents(c['input'] as num),
          BigInt.parse(c['cents'] as String),
        );
      });
    }
  });

  group('parseNaturalDate fixtures', () {
    for (final raw in fixtures['naturalDate'] as List) {
      final c = (raw as Map).cast<String, Object?>();
      final input = c['input'] as String;
      test(input, () {
        if (c['throws'] == true) {
          expect(() => parseNaturalDate(input, now: now), throwsA(anything));
          return;
        }
        final expected = _toDate((c['expect'] as Map).cast<String, Object?>());
        expect(
          parseNaturalDate(input, now: now),
          BigInt.from(expected.millisecondsSinceEpoch),
        );
      });
    }
  });

  group('parseTransactionDate fixtures', () {
    for (final raw in fixtures['transactionDate'] as List) {
      final c = (raw as Map).cast<String, Object?>();
      final date = c['date'] as String?;
      final status = _timeStatus(c['timeStatus'] as String);
      final time = c['time'] as String?;
      test('date=$date status=${c['timeStatus']} time=$time', () {
        if (c['throws'] == true) {
          expect(
            () => parseTransactionDate(
              date,
              timeStatus: status,
              time: time,
              now: now,
            ),
            throwsA(anything),
          );
          return;
        }
        final expected = _toDate((c['expect'] as Map).cast<String, Object?>());
        expect(
          parseTransactionDate(date, timeStatus: status, time: time, now: now),
          BigInt.from(expected.millisecondsSinceEpoch),
        );
      });
    }
  });
}
