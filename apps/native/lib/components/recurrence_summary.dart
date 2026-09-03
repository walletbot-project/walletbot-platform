/// How a recurring series reads in a receipt row. Shared by the
/// future-movements detail and the Activity detail: a movement that already
/// happened is still an occurrence of its rule, so both describe it the same
/// way.
library;

import 'package:flutter/widgets.dart';

import '../data/models/recurrence_series.dart';
import '../data/recurrence.dart';
import '../l10n/l10n.dart';

/// How a cadence reads in a sentence.
///
/// Deliberately the same catalogue the form offers, so a rule is described
/// identically where it is created and where it is read back. `customDays` is
/// the one that differs: the form shows the chip "Cada X días" with the
/// interval in its own field, while here the interval is part of the
/// description.
///
/// Null when this build does not know the stored cadence — a newer client may
/// have synced one added after this version shipped.
String? recurrenceFrequencyLabel(
  BuildContext context,
  RecurrenceSeries series,
) {
  final frequency = recurrenceFrequencyFromName(series.rule.frequency);
  if (frequency == null) return null;
  return switch (frequency) {
    RecurrenceFrequency.daily => context.l10n.recurrenceDaily,
    RecurrenceFrequency.weekly => context.l10n.recurrenceWeekly,
    RecurrenceFrequency.monthly => context.l10n.recurrenceMonthly,
    RecurrenceFrequency.yearly => context.l10n.recurrenceYearly,
    RecurrenceFrequency.customDays => context.l10n.recurrenceEveryNDays(
      series.rule.dayInterval ?? 1,
    ),
  };
}

/// What the series reaches, shown beside the cadence.
///
/// A bounded rule says where [occurrenceIndex] sits in it ("3/12"): the total
/// is knowable, so the position is the useful fact. An open-ended one has no
/// total to be a fraction of, so it says how far the movements that exist go
/// instead.
String? recurrenceReachLabel(
  BuildContext context,
  RecurrenceSeries series, {
  required int? occurrenceIndex,
}) {
  if (series.rule.endDate != null) {
    if (occurrenceIndex == null || series.count == 0) return null;
    return context.l10n.seriesPosition(occurrenceIndex + 1, series.count);
  }
  final covered = series.coveredThrough;
  if (covered == null) return null;
  return context.l10n.coveredThrough(
    formatNumericDate(covered, context.localeName),
  );
}
