import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../database.dart';

/// The boundary between a movement that has already happened and one that has
/// not — the Dart counterpart of `pastCutoffMs` in `@wallet-bot/shared`.
///
/// A recurring rule materialises its occurrences as ordinary rows in
/// `transactions` with future dates, so every read that describes what
/// happened — the activity list, an account balance, a category's spend, a
/// dashboard tile — stops here, and the upcoming list starts here. The split
/// is invisible to the user: neither side presents it as a filter.
///
/// **The boundary is the end of the current 20-minute block**, and it rounds
/// **up**. That is load-bearing: the cutoff is an exclusive upper bound, so
/// rounding down would put a movement recorded *right now* above it and make
/// the expense the user just entered vanish from the activity list for up to
/// twenty minutes.
///
/// Quantizing exists for the web, where the cutoff is a Convex query argument
/// and a value that changed every millisecond would miss the cache on every
/// call. It costs nothing here, and both platforms use the same grain so a
/// movement lands on the same side of the boundary on the phone and on the web
/// (`occurrence.test.ts` and `occurrence_test.dart` pin the same numbers).

/// How coarse the cutoff is, in seconds. Mirrors `OCCURRENCE_BUCKET_MS`.
const int occurrenceBucketSeconds = 20 * 60;

/// The end of the 20-minute block [now] falls in.
///
/// Always strictly after [now], including when [now] sits exactly on a
/// boundary — the same way the old day cutoff was always the *next* midnight.
BigInt pastCutoffMs([DateTime? now]) {
  final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final bucketMs = occurrenceBucketSeconds * 1000;
  return BigInt.from((ms ~/ bucketMs + 1) * bucketMs);
}

/// How long until the next block boundary has passed, measured from [now].
///
/// One second past the boundary, not on it: a timer that wakes a hair early
/// would compute the same cutoff and re-arm in a tight loop. Never negative,
/// so a boundary that went by while the process was suspended fires at once.
Duration occurrenceTickDelay([DateTime? now]) {
  final at = now ?? clock.now();
  final boundary = pastCutoffMs(at).toInt();
  final ms = boundary - at.millisecondsSinceEpoch;
  return Duration(milliseconds: ms < 0 ? 0 : ms) + const Duration(seconds: 1);
}

/// The cutoff as SQL, evaluated when the statement runs.
///
/// Not a bound Dart value, on purpose. Drift bakes a value into the statement
/// it builds and re-runs *that* statement when the tables change, so a
/// constant would freeze the cutoff for as long as the screen holding the
/// stream lives. Computed in SQL, every re-run of the query asks the clock
/// again — but drift only re-runs a stream when one of its tables changes, so
/// a screen left open with no writes would still sit on the old side of the
/// boundary. [AppDatabase.startOccurrenceClock] closes that gap: it marks
/// `transactions` updated one second past each boundary, which re-runs every
/// open stream against this expression.
///
/// `strftime('%s')` rather than `unixepoch()`: the latter needs SQLite 3.38,
/// and this has to hold on whatever the device ships.
const String pastCutoffSql =
    "((CAST(strftime('%s','now') AS INTEGER) / $occurrenceBucketSeconds + 1) "
    '* $occurrenceBucketSeconds * 1000)';

/// [pastCutoffSql] as a drift expression, for the query builders.
Expression<BigInt> pastCutoffExpression() =>
    const CustomExpression<BigInt>(pastCutoffSql);

/// Which side of the cutoff a read wants.
enum TxnOccurrence {
  /// Everything that has already happened. The default for every read that
  /// answers "what is my money doing".
  occurred,

  /// Everything a recurring rule has scheduled that has not happened yet.
  upcoming,
}

/// The cutoff predicate for [occurrence].
///
/// [now] pins the boundary for tests; production reads it from SQL so an open
/// stream keeps up.
Expression<bool> occurrenceFilter(
  $TransactionsTable t,
  TxnOccurrence occurrence, {
  DateTime? now,
}) {
  final cutoff = now == null
      ? pastCutoffExpression()
      : Constant<BigInt>(pastCutoffMs(now));
  switch (occurrence) {
    case TxnOccurrence.occurred:
      return t.date.isSmallerThan(cutoff);
    case TxnOccurrence.upcoming:
      return t.date.isBiggerOrEqual(cutoff);
  }
}
