import '../../database.dart';
import '../recurrence.dart';

/// A recurring rule together with where one of its occurrences sits in it.
///
/// Nothing here is stored on the rule: it is all derived from the occurrence
/// rows, which stay the only truth about how far a series got
/// (`docs/recurrency-design.md` §5.2).
///
/// [position] and [total] count the occurrences that **survive**, and are
/// deliberately not `recurrenceIndex + 1` and `maxIndex + 1`: a deleted
/// occurrence keeps its index, because that index is the key its date is
/// projected from and the marker that stops the materialiser recreating it.
/// So the index counts slots, and the user counts movements.
class RecurrenceSeries {
  const RecurrenceSeries({
    required this.rule,
    required this.position,
    required this.total,
    required this.coveredThrough,
  });

  final Recurrence rule;

  /// This occurrence's rank among the survivors, or null when the series is
  /// longer than [seriesCountCap] and was not counted.
  final int? position;

  /// Surviving occurrences, or null when the series is past the cap.
  final int? total;

  /// The date of the last surviving occurrence — how far the series goes.
  /// Null when there are none.
  final DateTime? coveredThrough;
}
