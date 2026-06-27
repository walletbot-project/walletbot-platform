import 'package:drift/drift.dart';

import '../../database.dart';

/// Per-transaction balance arithmetic. MUST stay identical to the replay in
/// `lib/sync/sync_recompute.dart` — if the two diverge, every sync cycle
/// "corrects" freshly created balance adjustments and amounts visibly jump
/// (guarded by test/sync/balance_recompute_test.dart).
///
/// Own side: expense/transfer subtract `amount`; income/balance_adjustment
/// add `amount`. Incoming transfers add `toAmount ?? amount`. Archived rows
/// are excluded by the queries below.
BigInt accountBalanceFromRows(List<Transaction> rows, String accountId) {
  BigInt sum = BigInt.zero;
  for (final t in rows) {
    if (t.accountId == accountId) {
      switch (t.type) {
        case 'expense':
        case 'transfer':
          sum -= t.amount;
          break;
        case 'income':
        case 'balance_adjustment':
          sum += t.amount;
          break;
      }
    }
    if (t.type == 'transfer' && t.toAccountId == accountId) {
      sum += t.toAmount ?? t.amount;
    }
  }
  return sum;
}

Expression<bool> _touchesAccount($TransactionsTable t, String accountId) =>
    t.accountId.equals(accountId) |
    (t.type.equals('transfer') & t.toAccountId.equals(accountId));

Future<BigInt> computeAccountBalance(AppDatabase db, String accountId) async {
  final rows =
      await (db.select(db.transactions)
            ..where((t) => t.archived.equals(false))
            ..where((t) => _touchesAccount(t, accountId)))
          .get();
  return accountBalanceFromRows(rows, accountId);
}

Stream<BigInt> watchAccountBalance(AppDatabase db, String accountId) {
  return (db.select(db.transactions)
        ..where((t) => t.archived.equals(false))
        ..where((t) => _touchesAccount(t, accountId)))
      .watch()
      .map((rows) => accountBalanceFromRows(rows, accountId));
}
