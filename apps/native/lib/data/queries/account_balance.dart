import 'dart:async';

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

/// Live total balance across every active account in [currency] — the sum of
/// each account's [accountBalanceFromRows] balance. Reactive to both account
/// changes (a new account, an archive) and transaction changes (any write or
/// sync merge), so a Balance-card widget stays current "as of now".
///
/// Reuses [accountBalanceFromRows] per account so the arithmetic can never
/// diverge from the per-account balance or the sync recompute.
Stream<BigInt> watchTotalBalanceForCurrency(AppDatabase db, String currency) {
  final accountsStream =
      (db.select(db.accounts)
            ..where((a) => a.archived.equals(false))
            ..where((a) => a.currency.equals(currency)))
          .watch();
  final txnsStream = (db.select(
    db.transactions,
  )..where((t) => t.archived.equals(false))).watch();
  return _combineLatest2(accountsStream, txnsStream, (accounts, txns) {
    var total = BigInt.zero;
    for (final a in accounts) {
      total += accountBalanceFromRows(txns, a.id);
    }
    return total;
  });
}

/// Combines the latest value of two streams, emitting once both have produced
/// at least one value and again on every later event from either. Avoids a
/// dependency on rxdart for the one place the dashboard needs it.
Stream<R> _combineLatest2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A, B) combine,
) {
  late StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  late A latestA;
  late B latestB;
  var hasA = false;
  var hasB = false;
  var doneA = false;
  var doneB = false;

  void emit() {
    if (hasA && hasB) controller.add(combine(latestA, latestB));
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen(
        (value) {
          latestA = value;
          hasA = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          doneA = true;
          if (doneB) controller.close();
        },
      );
      subB = b.listen(
        (value) {
          latestB = value;
          hasB = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          doneB = true;
          if (doneA) controller.close();
        },
      );
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}
