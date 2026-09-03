/// How far ahead a recurring rule with no end date is materialised — the Dart
/// counterpart of `packages/shared/src/recurrence.ts`. The two must agree: a
/// rule created on the phone and one created on the web have to produce the
/// same batch.
///
/// "No end date" cannot mean "forever": the occurrences are ordinary
/// transactions (see `docs/recurrency-design.md` §2.5), so an unbounded rule
/// would be an unbounded number of rows. Each frequency materialises a fixed
/// batch up front and the user tops it up when they want more — which is why
/// the form has to say so rather than quietly capping them.
library;

/// How many occurrences of a series the app will read to work out "the 3rd of
/// 12" — the Dart mirror of `SERIES_COUNT_CAP` in
/// `packages/shared/src/recurrence.ts`.
///
/// Position and total are counted over the occurrences that *survive*, which
/// cannot be derived from `recurrenceIndex`: a deleted occurrence keeps its
/// index (the delete is logical, and the index is the projection key), so the
/// highest index counts slots, not movements. Counting survivors means reading
/// them, so the read is capped and a series past the cap shows how far it
/// reaches instead.
///
/// Shared with web so both platforms fall back at the same size, even though
/// SQLite could count a bigger series for free.
const int seriesCountCap = 500;

/// Mean Gregorian month, so a day count converts without drifting over years.
const double _daysPerMonth = 365.2425 / 12;

enum RecurrenceSpanUnit { days, months, years }

/// How far a batch reaches, in whatever unit reads best for that batch.
class RecurrenceSpan {
  const RecurrenceSpan(this.unit, this.value);

  final RecurrenceSpanUnit unit;
  final int value;
}

class RecurrenceHorizon {
  const RecurrenceHorizon({required this.count, required this.span});

  /// Movements created up front for a rule with no end date.
  final int count;

  /// Roughly how far those movements reach.
  final RecurrenceSpan span;
}

/// The batch size for "every X days", picked from the cadence X resembles: a
/// few days behaves like daily, a couple of weeks like weekly, and so on. The
/// bands are half-open upwards — 7 is already weekly-ish, 365 already yearly.
int customDaysCount(int dayInterval) {
  final interval = dayInterval < 1 ? 1 : dayInterval;
  if (interval < 7) return 500;
  if (interval < 30) return 100;
  if (interval < 365) return 48;
  return 20;
}

/// Converts a total number of days into the coarsest unit that stays honest.
RecurrenceSpan _spanFromDays(int days) {
  final months = (days / _daysPerMonth).round();
  if (months >= 24) {
    return RecurrenceSpan(RecurrenceSpanUnit.years, (months / 12).round());
  }
  return RecurrenceSpan(RecurrenceSpanUnit.months, months);
}

/// The batch a rule with no end date materialises.
///
/// [dayInterval] is only read for `customDays`; the other frequencies have a
/// fixed batch. The spans of the fixed ones are exact by construction (48
/// months *is* 4 years); the computed ones are rounded, which is why the copy
/// that renders them hedges.
RecurrenceHorizon recurrenceHorizon(
  RecurrenceFrequency frequency, {
  int dayInterval = 1,
}) {
  switch (frequency) {
    case RecurrenceFrequency.daily:
      return const RecurrenceHorizon(
        count: 500,
        span: RecurrenceSpan(RecurrenceSpanUnit.days, 500),
      );
    case RecurrenceFrequency.weekly:
      // 100 weeks — 700 days, just under two years.
      return const RecurrenceHorizon(
        count: 100,
        span: RecurrenceSpan(RecurrenceSpanUnit.months, 23),
      );
    case RecurrenceFrequency.monthly:
      return const RecurrenceHorizon(
        count: 48,
        span: RecurrenceSpan(RecurrenceSpanUnit.years, 4),
      );
    case RecurrenceFrequency.yearly:
      return const RecurrenceHorizon(
        count: 20,
        span: RecurrenceSpan(RecurrenceSpanUnit.years, 20),
      );
    case RecurrenceFrequency.customDays:
      final interval = dayInterval < 1 ? 1 : dayInterval;
      final count = customDaysCount(interval);
      return RecurrenceHorizon(
        count: count,
        span: _spanFromDays(count * interval),
      );
  }
}

/// The cadence of a recurring rule. Declared here rather than in the form so
/// the policy above and the screens that render it share one definition.
enum RecurrenceFrequency { daily, weekly, monthly, yearly, customDays }

/// Parses the stored `frequency` string back into the enum, tolerating a value
/// this build does not know: the column is plain text and a newer client may
/// have synced a cadence added after this version shipped. Null means "cannot
/// interpret", which callers treat as "leave the series alone" rather than
/// guessing at it.
RecurrenceFrequency? recurrenceFrequencyFromName(String name) {
  for (final frequency in RecurrenceFrequency.values) {
    if (frequency.name == name) return frequency;
  }
  return null;
}

/// Days in a given local month, with [month] 1-based as in [DateTime.month].
/// Day 0 of the next month is the last day of this one.
int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// The date of the [index]-th occurrence of a rule anchored at [anchor]
/// (index 0 *is* the anchor). Mirror of `occurrenceDateMs` in
/// `packages/shared/src/recurrence.ts` — the two must agree, or a series
/// created on the phone would land on different days than one created on the
/// web.
///
/// Two rules, both from `docs/recurrency-design.md` §2.3:
///
/// 1. Every occurrence is projected from the anchor, never from the previous
///    one. Stepping month by month would let a February clipped to the 28th
///    drag the error forward and leave March on the 28th too.
/// 2. An anchor on the last day of its month means "last day of the month",
///    so 31 Jan monthly gives 28/29 Feb, 31 Mar, 30 Apr. An anchor that is not
///    the last day keeps its day number, clipped only where the month is
///    shorter.
///
/// All arithmetic is on local calendar components, so a DST boundary moves the
/// instant but never the calendar day or the wall-clock time.
DateTime occurrenceDate(
  DateTime anchor,
  RecurrenceFrequency frequency,
  int index, {
  int dayInterval = 1,
}) {
  DateTime byDays(int step) => DateTime(
    anchor.year,
    anchor.month,
    anchor.day + index * step,
    anchor.hour,
    anchor.minute,
    anchor.second,
    anchor.millisecond,
  );

  switch (frequency) {
    case RecurrenceFrequency.daily:
      return byDays(1);
    case RecurrenceFrequency.weekly:
      return byDays(7);
    case RecurrenceFrequency.customDays:
      return byDays(dayInterval < 1 ? 1 : dayInterval);
    case RecurrenceFrequency.monthly:
    case RecurrenceFrequency.yearly:
      final monthStep = frequency == RecurrenceFrequency.monthly
          ? index
          : index * 12;
      // `anchor.month` is 1-based; shift to 0-based for the modular maths.
      final absolute = (anchor.month - 1) + monthStep;
      final targetYear = anchor.year + (absolute ~/ 12);
      final targetMonth = (absolute % 12) + 1;
      final lastDayHere = _daysInMonth(anchor.year, anchor.month);
      final lastDayThere = _daysInMonth(targetYear, targetMonth);
      final targetDay = anchor.day == lastDayHere
          ? lastDayThere
          : (anchor.day < lastDayThere ? anchor.day : lastDayThere);
      return DateTime(
        targetYear,
        targetMonth,
        targetDay,
        anchor.hour,
        anchor.minute,
        anchor.second,
        anchor.millisecond,
      );
  }
}

/// How many occurrences a rule produces. Mirror of `occurrenceCount` in
/// `packages/shared/src/recurrence.ts`.
///
/// The batch exists only to give an *open-ended* rule a finite size. With an
/// [endDate] the user already said where the series stops, so all of its
/// occurrences get created — "monthly until 2036" means 120 movements, not the
/// first 48 of them. [endDate] is inclusive.
///
/// Binary search rather than stepping: the dates rise strictly with the index,
/// and "daily until 2050" is some 8,700 occurrences that nothing should have
/// to walk one at a time just to count them.
int occurrenceCount(
  DateTime anchor,
  RecurrenceFrequency frequency,
  DateTime? endDate, {
  int dayInterval = 1,
}) {
  if (endDate == null) {
    return recurrenceHorizon(frequency, dayInterval: dayInterval).count;
  }

  DateTime dateAt(int index) =>
      occurrenceDate(anchor, frequency, index, dayInterval: dayInterval);
  if (dateAt(0).isAfter(endDate)) return 0;

  var lo = 0;
  var hi = _indexUpperBound(anchor, frequency, endDate, dayInterval);
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (dateAt(mid).isAfter(endDate)) {
      hi = mid - 1;
    } else {
      lo = mid;
    }
  }
  return lo + 1;
}

/// An index guaranteed to be at or past the last occurrence on or before
/// [endDate] — the search's right edge.
///
/// Only ever an over-estimate. The day-based cadences step by calendar days
/// while this divides an elapsed duration, so a DST transition can shift the
/// quotient by a fraction of a day; the slack absorbs it.
int _indexUpperBound(
  DateTime anchor,
  RecurrenceFrequency frequency,
  DateTime endDate,
  int dayInterval,
) {
  switch (frequency) {
    case RecurrenceFrequency.monthly:
      final months =
          (endDate.year - anchor.year) * 12 + (endDate.month - anchor.month);
      return months + 2 < 0 ? 0 : months + 2;
    case RecurrenceFrequency.yearly:
      final years = endDate.year - anchor.year + 2;
      return years < 0 ? 0 : years;
    case RecurrenceFrequency.daily:
    case RecurrenceFrequency.weekly:
    case RecurrenceFrequency.customDays:
      final step = switch (frequency) {
        RecurrenceFrequency.weekly => 7,
        RecurrenceFrequency.daily => 1,
        _ => dayInterval < 1 ? 1 : dayInterval,
      };
      final days =
          endDate.difference(anchor).inMilliseconds /
          Duration.millisecondsPerDay;
      final bound = (days / step).floor() + 3;
      return bound < 0 ? 0 : bound;
  }
}

/// The rule a movement is being created under — what the form collected,
/// before it becomes a `recurrences` row.
class RecurrenceDraft {
  const RecurrenceDraft({
    required this.frequency,
    this.dayInterval = 1,
    this.endDate,
  });

  final RecurrenceFrequency frequency;

  /// Only meaningful for [RecurrenceFrequency.customDays].
  final int dayInterval;

  /// Inclusive. Null means open-ended, capped by the frequency's batch.
  final DateTime? endDate;
}
