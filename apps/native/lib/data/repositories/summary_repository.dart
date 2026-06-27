import 'package:drift/drift.dart';

import '../models/summaries.dart';
import 'repository_base.dart';

/// Aggregations over transactions (per-category totals, per-account flows).
/// Computed over the local database — fine at personal-finance scale; if a
/// summary ever needs to be reactive, add a `watch*` variant backed by the
/// same logic.
class SummaryRepository extends RepositoryBase {
  SummaryRepository(super.db);

  /// Per-category totals over a date window. Transfers are excluded; only
  /// active categories resolve a name (`(unknown)` otherwise).
  Future<List<CategoryTotal>> byCategory({
    required BigInt fromMs,
    required BigInt toMs,
    String? type,
    String? currency,
  }) async {
    final query = db.select(db.transactions)
      ..where((t) => t.archived.equals(false))
      ..where((t) => t.date.isBiggerOrEqualValue(fromMs))
      ..where((t) => t.date.isSmallerOrEqualValue(toMs));
    if (type != null) {
      query.where((t) => t.type.equals(type));
    }
    final items = await query.get();

    final totals = <String, BigInt>{};
    for (final t in items) {
      if (t.type == 'transfer') continue;
      if (currency != null && t.currency != currency) continue;
      totals[t.categoryId] = (totals[t.categoryId] ?? BigInt.zero) + t.amount;
    }

    final cats = await (db.select(
      db.categories,
    )..where((c) => c.archived.equals(false))).get();
    final nameById = {for (final c in cats) c.id: c.name};

    return [
      for (final e in totals.entries)
        CategoryTotal(
          categoryId: e.key,
          name: nameById[e.key] ?? '(unknown)',
          totalCents: e.value,
        ),
    ];
  }

  /// Per-account in/out flows over a date window. Expenses and outgoing
  /// transfers count as out; income and incoming transfers as in; balance
  /// adjustments land on the side of their sign.
  Future<List<AccountFlow>> byAccount({
    required BigInt fromMs,
    required BigInt toMs,
  }) async {
    final items =
        await (db.select(db.transactions)
              ..where((t) => t.archived.equals(false))
              ..where((t) => t.date.isBiggerOrEqualValue(fromMs))
              ..where((t) => t.date.isSmallerOrEqualValue(toMs)))
            .get();
    final accounts = await (db.select(
      db.accounts,
    )..where((a) => a.archived.equals(false))).get();

    final rows =
        <
          String,
          ({String name, String currency, BigInt inSum, BigInt outSum})
        >{};
    for (final a in accounts) {
      rows[a.id] = (
        name: a.name,
        currency: a.currency,
        inSum: BigInt.zero,
        outSum: BigInt.zero,
      );
    }

    for (final t in items) {
      final cur = rows[t.accountId];
      if (cur != null) {
        BigInt nextIn = cur.inSum;
        BigInt nextOut = cur.outSum;
        if (t.type == 'expense') {
          nextOut += t.amount;
        } else if (t.type == 'income') {
          nextIn += t.amount;
        } else if (t.type == 'transfer') {
          nextOut += t.amount;
        } else if (t.type == 'balance_adjustment') {
          if (t.amount >= BigInt.zero) {
            nextIn += t.amount;
          } else {
            nextOut += -t.amount;
          }
        }
        rows[t.accountId] = (
          name: cur.name,
          currency: cur.currency,
          inSum: nextIn,
          outSum: nextOut,
        );
      }
      if (t.type == 'transfer' && t.toAccountId != null) {
        final dest = rows[t.toAccountId];
        if (dest != null) {
          rows[t.toAccountId!] = (
            name: dest.name,
            currency: dest.currency,
            inSum: dest.inSum + (t.toAmount ?? t.amount),
            outSum: dest.outSum,
          );
        }
      }
    }

    return [
      for (final e in rows.entries)
        AccountFlow(
          accountId: e.key,
          name: e.value.name,
          currency: e.value.currency,
          inCents: e.value.inSum,
          outCents: e.value.outSum,
        ),
    ];
  }
}
