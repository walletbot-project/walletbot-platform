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
/// **The cutoff is the end of the local day, not the current instant.** A
/// movement dated today at 20:00 counts as having happened from the start of
/// the day, which is how the app behaved before recurrence existed. Cutting at
/// the instant would make a movement entered this morning for tonight vanish
/// from Activity until 20:00.
///
/// Unlike the web, nothing has to travel here: the device owns both the clock
/// and the database, and the local timezone is simply the device's.
BigInt pastCutoffMs([DateTime? now]) {
  final today = now ?? DateTime.now();
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  return BigInt.from(tomorrow.millisecondsSinceEpoch);
}

/// Which side of the cutoff a read wants.
enum TxnOccurrence {
  /// Everything that has already happened. The default for every read that
  /// answers "what is my money doing".
  occurred,

  /// Everything a recurring rule has scheduled that has not happened yet.
  upcoming,
}

/// The cutoff predicate for [occurrence].
Expression<bool> occurrenceFilter(
  $TransactionsTable t,
  TxnOccurrence occurrence, {
  DateTime? now,
}) {
  switch (occurrence) {
    case TxnOccurrence.occurred:
      return t.date.isSmallerThanValue(pastCutoffMs(now));
    case TxnOccurrence.upcoming:
      return t.date.isBiggerOrEqualValue(pastCutoffMs(now));
  }
}
