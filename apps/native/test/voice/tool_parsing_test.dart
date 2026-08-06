import 'package:app/database.dart';
import 'package:app/voice/tool_parsing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final reference = DateTime(2026, 7, 12, 14, 25, 30);

  test('parses deterministic relative weekdays in Spanish and English', () {
    for (final phrase in const ['el jueves pasado', 'last Thursday']) {
      final parsed = DateTime.fromMillisecondsSinceEpoch(
        parseNaturalDate(phrase, now: reference).toInt(),
      );
      expect(parsed, DateTime(2026, 7, 9));
    }
  });

  test('relative weekday always means the previous occurrence', () {
    final thursday = DateTime(2026, 7, 9, 10);
    final parsed = DateTime.fromMillisecondsSinceEpoch(
      parseNaturalDate('jueves pasado', now: thursday).toInt(),
    );
    expect(parsed, DateTime(2026, 7, 2));
  });

  test('parses relative day counts', () {
    final parsed = DateTime.fromMillisecondsSinceEpoch(
      parseNaturalDate('hace 3 días', now: reference).toInt(),
    );
    expect(parsed, DateTime(2026, 7, 9));
  });

  test('combines an exact time with today when date is omitted', () {
    final parsed = DateTime.fromMillisecondsSinceEpoch(
      parseTransactionDate(
        null,
        timeStatus: TransactionTimeStatus.confirmed,
        time: '17:00',
        now: reference,
      ).toInt(),
    );
    expect(parsed, DateTime(2026, 7, 12, 17));
  });

  test('combines an exact time with a relative calendar day', () {
    final parsed = DateTime.fromMillisecondsSinceEpoch(
      parseTransactionDate(
        'el jueves pasado',
        timeStatus: TransactionTimeStatus.confirmed,
        time: '17:00',
        now: reference,
      ).toInt(),
    );
    expect(parsed, DateTime(2026, 7, 9, 17));
  });

  test('requires a time when timeStatus is confirmed or approximation', () {
    for (final status in const [
      TransactionTimeStatus.confirmed,
      TransactionTimeStatus.approximation,
    ]) {
      expect(
        () => parseTransactionDate('ayer', timeStatus: status, now: reference),
        throwsArgumentError,
        reason:
            'a $status hour without a clock must be rejected, not '
            'silently anchored to midnight',
      );
    }
  });

  test('approximation with a representative clock keeps day and hour', () {
    final parsed = DateTime.fromMillisecondsSinceEpoch(
      parseTransactionDate(
        'ayer',
        timeStatus: TransactionTimeStatus.approximation,
        time: '16:00',
        now: reference,
      ).toInt(),
    );
    expect(parsed, DateTime(2026, 7, 11, 16));
  });
}
