import '../data/balance_adjustments.dart';
import '../database.dart';

/// Re-derives every `balance_adjustment.amount` from the ledger before it so
/// each adjustment still lands on its `balanceAfter`. Runs after every pull:
/// rows merged from other devices — a movement back-dated before an
/// adjustment, say — change what came before it.
///
/// The rule lives in `lib/data/balance_adjustments.dart`, shared with the
/// repositories' own write path. Corrected rows are marked `dirty = true` so
/// the next push round propagates the recomputed amount back to the server.
///
/// Returns the number of rows whose `amount` was corrected.
class BalanceAdjustmentRecomputer {
  BalanceAdjustmentRecomputer(this.db);
  final AppDatabase db;

  Future<int> recompute() => reconcileLocalAdjustments(db);
}
