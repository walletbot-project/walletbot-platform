import 'package:drift/drift.dart';

import '../database.dart';

/// Replays every transaction per account in `date` ascending order to verify
/// that each `balance_adjustment.amount` still produces its `balanceAfter`.
/// If a recent inflow/outflow was inserted "in the past" by another device,
/// the original amount becomes stale and gets corrected here.
///
/// Corrected rows are marked `dirty = true` so the next push round
/// propagates the recomputed amount back to the server.
///
/// Returns the number of rows whose `amount` was corrected.
class BalanceAdjustmentRecomputer {
  BalanceAdjustmentRecomputer(this.db);
  final AppDatabase db;

  Future<int> recompute() async {
    // Pull every active transaction in one shot. The spec assumes the user's
    // transaction count fits in memory; for personal finance this is true
    // for years of data. If we ever cross that line we can chunk per
    // account.
    final txns = await (db.select(
      db.transactions,
    )..where((t) => t.archived.equals(false))).get();
    if (txns.isEmpty) return 0;

    // Index by account: each row contributes either to its `accountId`
    // (always) or to `toAccountId` (transfers only).
    final byAccount = <String, List<_Event>>{};
    for (final t in txns) {
      final list = byAccount.putIfAbsent(t.accountId, () => <_Event>[]);
      list.add(_Event(t.date, _EventKind.own, t));
      if (t.type == 'transfer' && t.toAccountId != null) {
        final dest = byAccount.putIfAbsent(
          t.toAccountId as String,
          () => <_Event>[],
        );
        dest.add(_Event(t.date, _EventKind.incoming, t));
      }
    }

    int corrections = 0;
    await db.transaction(() async {
      for (final entry in byAccount.entries) {
        final events = entry.value
          // Stable sort: by date asc, then balance_adjustment last among
          // same-date events so it observes the day's net change.
          ..sort((a, b) {
            final cmp = a.date.compareTo(b.date);
            if (cmp != 0) return cmp;
            final aAdj = a.txn.type == 'balance_adjustment' ? 1 : 0;
            final bAdj = b.txn.type == 'balance_adjustment' ? 1 : 0;
            return aAdj - bAdj;
          });

        BigInt balance = BigInt.zero;
        for (final ev in events) {
          final t = ev.txn;
          if (ev.kind == _EventKind.incoming) {
            balance += t.toAmount ?? t.amount;
            continue;
          }
          if (t.type == 'balance_adjustment') {
            final target = t.balanceAfter ?? balance;
            final expected = target - balance;
            if (expected != t.amount) {
              await (db.update(
                db.transactions,
              )..where((row) => row.id.equals(t.id))).write(
                TransactionsCompanion(
                  amount: Value(expected),
                  updatedAt: Value(
                    BigInt.from(DateTime.now().millisecondsSinceEpoch),
                  ),
                  dirty: const Value(true),
                ),
              );
              corrections += 1;
              balance = target;
            } else {
              balance += t.amount;
            }
            continue;
          }
          // own non-adjustment event:
          switch (t.type) {
            case 'expense':
            case 'transfer':
              balance -= t.amount;
              break;
            case 'income':
              balance += t.amount;
              break;
          }
        }
      }
    });
    return corrections;
  }
}

enum _EventKind { own, incoming }

class _Event {
  _Event(this.date, this.kind, this.txn);
  final BigInt date;
  final _EventKind kind;
  final Transaction txn;
}
