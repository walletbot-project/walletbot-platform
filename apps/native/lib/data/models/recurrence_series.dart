import '../../database.dart';

/// A recurring rule together with how far its series currently reaches.
///
/// [count] and [coveredThrough] are read off the last occurrence rather than
/// stored on the rule: occurrence indices run contiguously from 0, so the
/// highest index *is* the count. Keeping them derived means the rows stay the
/// only truth about how far a series got
/// (`docs/recurrency-design.md` §5.2).
class RecurrenceSeries {
  const RecurrenceSeries({
    required this.rule,
    required this.count,
    required this.coveredThrough,
  });

  final Recurrence rule;

  /// Occurrences that exist. Zero only while the series is empty.
  final int count;

  /// The date of the last occurrence — how far the series goes. Null when
  /// there are none.
  final DateTime? coveredThrough;
}
