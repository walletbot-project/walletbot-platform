import 'package:drift/drift.dart';

import '../../database.dart';
import 'stream_utils.dart';

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

/// Live total balance across the active accounts in [currency] — the sum of
/// each account's [accountBalanceFromRows] balance. Reactive to both account
/// changes (a new account, an archive) and transaction changes (any write or
/// sync merge), so a Balance-card widget stays current "as of now".
///
/// [accountIds] narrows the sum to those accounts; empty (the default) is every
/// account in [currency], which is what every Balance card stored before
/// account scoping existed. Ids are still intersected with [currency], so a
/// stale id — an account since archived, deleted, or re-denominated — drops out
/// of the sum instead of being counted.
///
/// Reuses [accountBalanceFromRows] per account so the arithmetic can never
/// diverge from the per-account balance or the sync recompute.
Stream<BigInt> watchTotalBalanceForCurrency(
  AppDatabase db,
  String currency, {
  List<String> accountIds = const [],
}) {
  final scope = accountIds.toSet();
  final accountsStream =
      (db.select(db.accounts)
            ..where((a) => a.archived.equals(false))
            ..where((a) => a.currency.equals(currency)))
          .watch();
  final txnsStream = (db.select(
    db.transactions,
  )..where((t) => t.archived.equals(false))).watch();
  return combineLatest2(accountsStream, txnsStream, (accounts, txns) {
    var total = BigInt.zero;
    for (final a in accounts) {
      if (scope.isNotEmpty && !scope.contains(a.id)) continue;
      total += accountBalanceFromRows(txns, a.id);
    }
    return total;
  });
}
