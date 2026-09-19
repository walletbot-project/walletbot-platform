import 'package:app/data/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `packages/shared/test/recurrence.test.ts`. The two projections must
/// agree: a series created on the phone has to land on the same days as one
/// created on the web, or the same rule produces two different sets of rows.
void main() {
  List<String> project(
    DateTime anchor,
    RecurrenceFrequency frequency,
    int howMany, {
    int dayInterval = 1,
  }) => [
    for (var i = 0; i < howMany; i++)
      () {
        final d = occurrenceDate(
          anchor,
          frequency,
          i,
          dayInterval: dayInterval,
        );
        final mm = d.month.toString().padLeft(2, '0');
        final dd = d.day.toString().padLeft(2, '0');
        return '${d.year}-$mm-$dd';
      }(),
  ];

  group('month-end inference (docs/recurrency-design.md §2.3)', () {
    test('treats a last-day anchor as "last day of the month"', () {
      expect(project(DateTime(2026, 1, 31), RecurrenceFrequency.monthly, 6), [
        '2026-01-31',
        '2026-02-28',
        '2026-03-31',
        '2026-04-30',
        '2026-05-31',
        '2026-06-30',
      ]);
    });

    test('keeps the day number when the anchor is not the last day', () {
      expect(project(DateTime(2026, 1, 30), RecurrenceFrequency.monthly, 4), [
        '2026-01-30',
        '2026-02-28',
        '2026-03-30',
        '2026-04-30',
      ]);
    });

    test('does not drift: a clipped February never shortens March', () {
      expect(
        project(DateTime(2026, 1, 31), RecurrenceFrequency.monthly, 3)[2],
        '2026-03-31',
      );
    });

    test('uses 29 February in a leap year for a last-day anchor', () {
      expect(
        project(DateTime(2027, 1, 31), RecurrenceFrequency.monthly, 2)[1],
        '2027-02-28',
      );
      expect(
        project(DateTime(2028, 1, 31), RecurrenceFrequency.monthly, 2)[1],
        '2028-02-29',
      );
    });

    test('clamps a 29 February anchor to 28 in non-leap years', () {
      expect(project(DateTime(2028, 2, 29), RecurrenceFrequency.yearly, 5), [
        '2028-02-29',
        '2029-02-28',
        '2030-02-28',
        '2031-02-28',
        '2032-02-29',
      ]);
    });
  });

  group('day-based frequencies', () {
    test('steps daily across a month boundary', () {
      expect(project(DateTime(2026, 1, 30), RecurrenceFrequency.daily, 4), [
        '2026-01-30',
        '2026-01-31',
        '2026-02-01',
        '2026-02-02',
      ]);
    });

    test('steps weekly', () {
      expect(project(DateTime(2026, 1, 1), RecurrenceFrequency.weekly, 3), [
        '2026-01-01',
        '2026-01-08',
        '2026-01-15',
      ]);
    });

    test('steps by the custom interval', () {
      expect(
        project(
          DateTime(2026, 1, 1),
          RecurrenceFrequency.customDays,
          3,
          dayInterval: 45,
        ),
        ['2026-01-01', '2026-02-15', '2026-04-01'],
      );
    });

    test('keeps the wall-clock time rather than the instant', () {
      final anchor = DateTime(2026, 1, 1, 9);
      expect(occurrenceDate(anchor, RecurrenceFrequency.daily, 200).hour, 9);
    });
  });

  group('open-ended horizons', () {
    test('matches the agreed batch per frequency', () {
      expect(recurrenceHorizon(RecurrenceFrequency.daily).count, 500);
      expect(recurrenceHorizon(RecurrenceFrequency.weekly).count, 100);
      expect(recurrenceHorizon(RecurrenceFrequency.monthly).count, 48);
      expect(recurrenceHorizon(RecurrenceFrequency.yearly).count, 20);

      expect(
        recurrenceHorizon(RecurrenceFrequency.daily).span.unit,
        RecurrenceSpanUnit.days,
      );
      expect(recurrenceHorizon(RecurrenceFrequency.daily).span.value, 500);
      expect(
        recurrenceHorizon(RecurrenceFrequency.weekly).span.unit,
        RecurrenceSpanUnit.months,
      );
      expect(recurrenceHorizon(RecurrenceFrequency.weekly).span.value, 23);
      expect(
        recurrenceHorizon(RecurrenceFrequency.monthly).span.unit,
        RecurrenceSpanUnit.years,
      );
      expect(recurrenceHorizon(RecurrenceFrequency.monthly).span.value, 4);
      expect(recurrenceHorizon(RecurrenceFrequency.yearly).span.value, 20);
    });

    test('picks the custom batch from the band the interval falls in', () {
      expect(customDaysCount(1), 500);
      expect(customDaysCount(6), 500);
      expect(customDaysCount(7), 100);
      expect(customDaysCount(29), 100);
      expect(customDaysCount(30), 48);
      expect(customDaysCount(364), 48);
      expect(customDaysCount(365), 20);
      expect(customDaysCount(400), 20);
    });

    test('spans the custom batch in months or years', () {
      final threeDaily = recurrenceHorizon(
        RecurrenceFrequency.customDays,
        dayInterval: 3,
      );
      expect(threeDaily.span.unit, RecurrenceSpanUnit.years);
      expect(threeDaily.span.value, 4);

      final everyDay = recurrenceHorizon(
        RecurrenceFrequency.customDays,
        dayInterval: 1,
      );
      expect(everyDay.span.unit, RecurrenceSpanUnit.months);
      expect(everyDay.span.value, 16);
    });
  });

  group('per-call cap', () {
    test('is five open-ended batches of the frequency', () {
      expect(occurrenceCapMultiplier, 5);
      expect(maxOccurrenceCount(RecurrenceFrequency.daily), 2500);
      expect(maxOccurrenceCount(RecurrenceFrequency.weekly), 500);
      expect(maxOccurrenceCount(RecurrenceFrequency.monthly), 240);
      expect(maxOccurrenceCount(RecurrenceFrequency.yearly), 100);
      expect(
        maxOccurrenceCount(RecurrenceFrequency.customDays, dayInterval: 10),
        500,
      );
    });

    test('is what "daily until 2050" runs into', () {
      final total = occurrenceCount(
        DateTime(2026, 1, 1),
        RecurrenceFrequency.daily,
        DateTime(2050, 1, 1),
      );
      expect(total, greaterThan(maxOccurrenceCount(RecurrenceFrequency.daily)));
    });
  });

  group('occurrence count', () {
    test('is the horizon when the rule is open-ended', () {
      expect(
        occurrenceCount(
          DateTime(2026, 1, 1),
          RecurrenceFrequency.monthly,
          null,
        ),
        48,
      );
    });

    test('stops at an inclusive end date', () {
      expect(
        occurrenceCount(
          DateTime(2026, 1, 15),
          RecurrenceFrequency.monthly,
          DateTime(2026, 3, 15),
        ),
        3,
      );
    });

    test('excludes an end date that falls between occurrences', () {
      expect(
        occurrenceCount(
          DateTime(2026, 1, 15),
          RecurrenceFrequency.monthly,
          DateTime(2026, 3, 14),
        ),
        2,
      );
    });

    test('creates every occurrence up to a distant end date', () {
      // The batch is only there to give an *open-ended* rule a finite size.
      // "Monthly until 2036" means 120 movements, not the first 48 of them.
      expect(
        occurrenceCount(
          DateTime(2026, 1, 15),
          RecurrenceFrequency.monthly,
          DateTime(2036, 1, 15),
        ),
        121,
      );
      expect(
        occurrenceCount(
          DateTime(2026, 1, 15),
          RecurrenceFrequency.monthly,
          DateTime(2036, 1, 14),
        ),
        120,
      );
    });

    test('counts a long day-based series exactly', () {
      // 2028 is a leap year: 2026-01-01 to 2030-01-01 is 1461 days, so 1462
      // daily occurrences counting both ends.
      expect(
        occurrenceCount(
          DateTime(2026, 1, 1),
          RecurrenceFrequency.daily,
          DateTime(2030, 1, 1),
        ),
        1462,
      );
      expect(
        occurrenceCount(
          DateTime(2026, 1, 1),
          RecurrenceFrequency.weekly,
          DateTime(2030, 1, 1),
        ),
        1461 ~/ 7 + 1,
      );
      expect(
        occurrenceCount(
          DateTime(2026, 1, 1),
          RecurrenceFrequency.customDays,
          DateTime(2030, 1, 1),
          dayInterval: 10,
        ),
        1461 ~/ 10 + 1,
      );
    });

    test('counts a yearly series past its open-ended batch', () {
      expect(
        occurrenceCount(
          DateTime(2026, 3, 1),
          RecurrenceFrequency.yearly,
          DateTime(2076, 3, 1),
        ),
        51,
      );
    });

    test('agrees with stepping one occurrence at a time', () {
      // The count is found by binary search; this is the naive walk it
      // replaced, kept as the oracle.
      final anchor = DateTime(2026, 1, 31, 9);
      final cases = <(RecurrenceFrequency, DateTime)>[
        (RecurrenceFrequency.daily, DateTime(2026, 4, 17)),
        (RecurrenceFrequency.weekly, DateTime(2027, 2, 2)),
        (RecurrenceFrequency.monthly, DateTime(2031, 7, 15)),
        (RecurrenceFrequency.yearly, DateTime(2044, 1, 30)),
      ];
      for (final (frequency, end) in cases) {
        var walked = 0;
        while (!occurrenceDate(anchor, frequency, walked).isAfter(end)) {
          walked += 1;
        }
        expect(occurrenceCount(anchor, frequency, end), walked);
      }
    });

    test('is zero when the end date precedes the anchor', () {
      expect(
        occurrenceCount(
          DateTime(2026, 1, 15),
          RecurrenceFrequency.monthly,
          DateTime(2025, 12, 1),
        ),
        0,
      );
    });
  });
}
