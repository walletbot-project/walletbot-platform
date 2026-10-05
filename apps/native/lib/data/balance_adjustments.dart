import 'package:drift/drift.dart';

import '../database.dart';

/// A balance adjustment is a declaration — "right now this account holds
/// `balanceAfter`" — not a movement of a fixed amount. `balanceAfter` is what
/// the user declared and is never modified; `amount` is only the difference
/// between that declaration and what the ledger held at that moment, and it is
/// derived, never entered.
///
/// Because `amount` is derived from the past, it changes whenever the past
/// does: recording, editing or deleting a movement dated before an adjustment
/// re-derives that adjustment so the declaration still holds. Movements dated
/// after it never touch it.
///
/// Mirrors `packages/shared/src/balance-adjustment.ts`, which the backend
/// applies; both are checked against
/// `packages/shared/src/balance-adjustment-fixtures.json`
/// (test/data/balance_adjustment_fixtures_test.dart). If the two diverge, each
/// side rewrites the other's amounts on every sync.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.accountId,
    this.toAccountId,
    required this.amount,
    this.toAmount,
    this.balanceAfter,
    required this.date,
    required this.createdAt,
    this.archived = false,
  });

  factory LedgerEntry.fromTransaction(Transaction t) => LedgerEntry(
    id: t.id,
    type: t.type,
    accountId: t.accountId,
    toAccountId: t.toAccountId,
    amount: t.amount,
    toAmount: t.toAmount,
    balanceAfter: t.balanceAfter,
    date: t.date,
    createdAt: t.createdAt,
    archived: t.archived,
  );

  final String id;
  final String type;
  final String accountId;
  final String? toAccountId;
  final BigInt amount;
  final BigInt? toAmount;
  final BigInt? balanceAfter;
  final BigInt date;
  final BigInt createdAt;
  final bool archived;

  bool get isAdjustment => type == 'balance_adjustment';
}

/// Signed effect of [entry] on [accountId]'s balance: as its source, or as the
/// destination of a transfer. Archived entries have no effect.
BigInt ledgerDelta(LedgerEntry entry, String accountId) {
  if (entry.archived) return BigInt.zero;
  var delta = BigInt.zero;
  if (entry.accountId == accountId) {
    switch (entry.type) {
      case 'expense':
      case 'transfer':
        delta -= entry.amount;
        break;
      case 'income':
      case 'balance_adjustment':
        delta += entry.amount;
        break;
    }
  }
  if (entry.type == 'transfer' && entry.toAccountId == accountId) {
    delta += entry.toAmount ?? entry.amount;
  }
  return delta;
}

/// Ledger order: by date; at the exact same date every other movement comes
/// before an adjustment, so the adjustment observes it; then by creation, then
/// by id so the order is total.
int compareLedgerOrder(LedgerEntry a, LedgerEntry b) {
  final byDate = a.date.compareTo(b.date);
  if (byDate != 0) return byDate;
  if (a.isAdjustment != b.isAdjustment) return a.isAdjustment ? 1 : -1;
  final byCreation = a.createdAt.compareTo(b.createdAt);
  if (byCreation != 0) return byCreation;
  return a.id.compareTo(b.id);
}

/// What the platform computed for the account just before [adjustment] — the
/// figure shown next to the declared one. Derived from the stored pair, so it
/// follows the amount whenever the past changes.
BigInt adjustmentPreviousBalance({
  required BigInt amount,
  required BigInt balanceAfter,
}) => balanceAfter - amount;

/// [accountId]'s balance from every live entry before [entry] in ledger
/// order. [entry] need not be among [entries]: an adjustment about to be
/// inserted is measured the same way, so it is created with its final amount.
BigInt balanceBeforeInLedger(
  Iterable<LedgerEntry> entries,
  String accountId,
  LedgerEntry entry,
) {
  var balance = BigInt.zero;
  for (final e in entries) {
    if (e.id == entry.id) continue;
    if (compareLedgerOrder(e, entry) < 0) balance += ledgerDelta(e, accountId);
  }
  return balance;
}

/// Replays [entries] in ledger order and returns the correct amount of every
/// live adjustment on [accountIds] (every account when null), keyed by id.
///
/// An adjustment without `balanceAfter` declares whatever the balance already
/// was, so its amount is zero.
Map<String, BigInt> reconcileAdjustments(
  Iterable<LedgerEntry> entries, {
  Set<String>? accountIds,
}) {
  final live = entries.where((e) => !e.archived).toList()
    ..sort(compareLedgerOrder);
  final accounts =
      accountIds ??
      {
        for (final e in live) ...[
          e.accountId,
          if (e.type == 'transfer' && e.toAccountId != null) e.toAccountId!,
        ],
      };
  final amounts = <String, BigInt>{};
  for (final accountId in accounts) {
    var balance = BigInt.zero;
    for (final e in live) {
      if (e.isAdjustment && e.accountId == accountId) {
        final amount = (e.balanceAfter ?? balance) - balance;
        amounts[e.id] = amount;
        balance += amount;
        continue;
      }
      balance += ledgerDelta(e, accountId);
    }
  }
  return amounts;
}

/// Every live row that moves one of [accountIds] (every row when null).
Future<List<Transaction>> _ledgerRows(AppDatabase db, Set<String>? accountIds) {
  final query = db.select(db.transactions)
    ..where((t) => t.archived.equals(false));
  if (accountIds != null) {
    query.where(
      (t) =>
          t.accountId.isIn(accountIds) |
          (t.type.equals('transfer') & t.toAccountId.isIn(accountIds)),
    );
  }
  return query.get();
}

/// [accountId]'s balance just before [entry] in the local ledger.
Future<BigInt> localBalanceBeforeInLedger(
  AppDatabase db,
  String accountId,
  LedgerEntry entry,
) async {
  final rows = await _ledgerRows(db, {accountId});
  return balanceBeforeInLedger(
    rows.map(LedgerEntry.fromTransaction),
    accountId,
    entry,
  );
}

/// Re-derives the amount of every adjustment on [accountIds] (every account
/// when null) in the local database. Corrected rows are re-dirtied so the next
/// push carries the new amount — the same value the backend derives on its
/// side, so the two converge instead of fighting. Returns how many rows were
/// corrected.
///
/// Repositories call this inside the write's own `db.transaction`, so an
/// adjustment is never observed out of step with the movement that moved it;
/// the sync engine calls it after every pull.
Future<int> reconcileLocalAdjustments(
  AppDatabase db, {
  Set<String>? accountIds,
}) async {
  if (accountIds != null && accountIds.isEmpty) return 0;
  var corrections = 0;
  await db.transaction(() async {
    final rows = await _ledgerRows(db, accountIds);
    if (rows.isEmpty) return;
    final byId = {for (final row in rows) row.id: row};
    final amounts = reconcileAdjustments(
      rows.map(LedgerEntry.fromTransaction),
      accountIds: accountIds,
    );
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    for (final MapEntry(key: id, value: amount) in amounts.entries) {
      if (byId[id]?.amount == amount) continue;
      await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          amount: Value(amount),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      corrections += 1;
    }
  });
  return corrections;
}
