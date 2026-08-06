import 'package:drift/drift.dart';

import '../../database.dart';
import '../../telemetry/business_metrics.dart';
import '../ids.dart';
import '../models/transaction_filter.dart';
import '../queries/account_balance.dart';
import '../queries/transaction_query.dart';
import 'repository_base.dart';

/// Reads and writes for transactions (expenses, incomes, transfers, balance
/// adjustments) and their tag joins. Filtered reads go through the single
/// shared query builder in `queries/transaction_query.dart`.
class TransactionRepository extends RepositoryBase {
  TransactionRepository(super.db, {BusinessMetrics? businessMetrics})
    : _businessMetrics = businessMetrics;

  final BusinessMetrics? _businessMetrics;

  // ───── Reads ─────

  /// THE shared read path for filtered transaction lists. Reactive to local
  /// writes, agent writes, and sync merges (Drift stream). When the filter
  /// uses `includeSubtags`, the tag expansion itself re-resolves when the tag
  /// tree changes.
  Stream<List<Transaction>> watch(
    TransactionFilter filter, {
    int? limit,
    TxnOrdering ordering = TxnOrdering.createdAtDesc,
  }) => watchFilteredTransactions(db, filter, limit: limit, ordering: ordering);

  /// One-shot variant of [watch], used by the agent tools.
  /// [exactFromMs]/[exactToInclusiveMs] add precise inclusive timestamp
  /// bounds on top of the filter (the agent's dates are exact instants, not
  /// day ranges).
  Future<List<Transaction>> list(
    TransactionFilter filter, {
    int? limit,
    TxnOrdering ordering = TxnOrdering.dateDesc,
    BigInt? exactFromMs,
    BigInt? exactToInclusiveMs,
  }) async {
    List<Set<String>> groups;
    List<Tag> tags = const [];
    if (!filter.rootGroup.containsSubtagExpansion) {
      groups = expandTagGroups(filter, const []);
    } else {
      tags = await (db.select(
        db.tags,
      )..where((t) => t.archived.equals(false))).get();
      groups = expandTagGroups(filter, tags);
    }
    return buildTransactionQuery(
      db,
      filter,
      tagGroups: groups,
      activeTags: tags,
      limit: limit,
      ordering: ordering,
      exactFromMs: exactFromMs,
      exactToInclusiveMs: exactToInclusiveMs,
    ).get();
  }

  /// Exact-id lookup; finds archived transactions too. Null when missing.
  Future<Transaction?> getById(String id) => (db.select(
    db.transactions,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Ids of the tags currently attached to a transaction.
  Future<List<String>> tagIdsOf(String transactionId) async {
    final joins = await (db.select(
      db.transactionTags,
    )..where((j) => j.transactionId.equals(transactionId))).get();
    return joins.map((j) => j.tagId).toList();
  }

  /// Replays the local ledger for [accountId] and returns the balance
  /// immediately before and after [transactionId].
  Future<AccountBalanceAroundTransaction?> balanceAroundTransaction({
    required String transactionId,
    required String accountId,
  }) async {
    final rows =
        await (db.select(db.transactions)
              ..where((t) => t.archived.equals(false))
              ..where(
                (t) =>
                    t.accountId.equals(accountId) |
                    (t.type.equals('transfer') &
                        t.toAccountId.equals(accountId)),
              ))
            .get();

    rows.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      final createdCompare = a.createdAt.compareTo(b.createdAt);
      if (createdCompare != 0) return createdCompare;
      return a.id.compareTo(b.id);
    });

    var running = BigInt.zero;
    for (final row in rows) {
      final before = running;
      running += _accountDelta(row, accountId);
      if (row.id == transactionId) {
        return AccountBalanceAroundTransaction(before: before, after: running);
      }
    }
    return null;
  }

  // ───── Writes ─────

  /// Creates an expense (insert + tag attach in one transaction) and returns
  /// its id. [currency] is the owning account's currency — resolve it at the
  /// call site. [dateMs] defaults to now.
  Future<String> addExpense({
    required String accountId,
    required String categoryId,
    required String name,
    required BigInt amountCents,
    required String currency,
    String createdBy = 'form',
    String? description,
    String status = 'cleared',
    BigInt? dateMs,
    bool dateConfirmed = true,
    TransactionTimeStatus timeStatus = TransactionTimeStatus.none,
    List<String> tagIds = const [],
  }) => _addSimple(
    type: 'expense',
    accountId: accountId,
    categoryId: categoryId,
    name: name,
    amountCents: amountCents,
    currency: currency,
    description: description,
    status: status,
    dateMs: dateMs,
    dateConfirmed: dateConfirmed,
    timeStatus: timeStatus,
    tagIds: tagIds,
    createdBy: createdBy,
  );

  /// Creates an income. Same shape and semantics as [addExpense].
  Future<String> addIncome({
    required String accountId,
    required String categoryId,
    required String name,
    required BigInt amountCents,
    required String currency,
    String createdBy = 'form',
    String? description,
    String status = 'cleared',
    BigInt? dateMs,
    bool dateConfirmed = true,
    TransactionTimeStatus timeStatus = TransactionTimeStatus.none,
    List<String> tagIds = const [],
  }) => _addSimple(
    type: 'income',
    accountId: accountId,
    categoryId: categoryId,
    name: name,
    amountCents: amountCents,
    currency: currency,
    description: description,
    status: status,
    dateMs: dateMs,
    dateConfirmed: dateConfirmed,
    timeStatus: timeStatus,
    tagIds: tagIds,
    createdBy: createdBy,
  );

  Future<String> _addSimple({
    required String type,
    required String accountId,
    required String categoryId,
    required String name,
    required BigInt amountCents,
    required String currency,
    required String? description,
    required String status,
    required BigInt? dateMs,
    required bool dateConfirmed,
    required TransactionTimeStatus timeStatus,
    required List<String> tagIds,
    required String createdBy,
  }) async {
    final id = newUuid();
    final now = currentMs;
    await db.transaction(() async {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: id,
              type: type,
              name: name,
              description: Value(description),
              status: status,
              date: _resolveTransactionDate(
                dateMs: dateMs,
                timeStatus: timeStatus,
                loadedAtMs: now,
              ),
              timeStatus: Value(timeStatus),
              accountId: accountId,
              categoryId: categoryId,
              amount: amountCents,
              currency: currency,
              dateConfirmed: Value(dateConfirmed),
              createdAt: now,
              updatedAt: now,
              dirty: const Value(true),
            ),
          );
      await _attachTagsTx(id, tagIds, now);
    });
    _trackCreatedMetric(type: type, createdBy: createdBy);
    return id;
  }

  /// Creates a transfer between two different accounts and returns its id.
  /// Throws [ArgumentError] when source and destination are the same.
  ///
  /// [toAmountCents]/[toCurrency] must be pre-resolved by the caller
  /// (same-currency transfers pass the source amount/currency; cross-currency
  /// callers must provide the destination amount).
  Future<String> addTransfer({
    required String fromAccountId,
    required String toAccountId,
    required String name,
    required BigInt amountCents,
    required String currency,
    required BigInt toAmountCents,
    required String toCurrency,
    String createdBy = 'form',
    double? exchangeRate,
    String categoryId = '',
    String? description,
    String status = 'cleared',
    BigInt? dateMs,
    bool dateConfirmed = true,
    TransactionTimeStatus timeStatus = TransactionTimeStatus.none,
    List<String> tagIds = const [],
  }) async {
    if (fromAccountId == toAccountId) {
      throw ArgumentError('Source and destination accounts must differ');
    }
    final id = newUuid();
    final now = currentMs;
    await db.transaction(() async {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: id,
              type: 'transfer',
              name: name,
              description: Value(description),
              status: status,
              date: _resolveTransactionDate(
                dateMs: dateMs,
                timeStatus: timeStatus,
                loadedAtMs: now,
              ),
              timeStatus: Value(timeStatus),
              accountId: fromAccountId,
              categoryId: categoryId,
              amount: amountCents,
              currency: currency,
              toAccountId: Value(toAccountId),
              toAmount: Value(toAmountCents),
              toCurrency: Value(toCurrency),
              exchangeRate: Value(exchangeRate),
              dateConfirmed: Value(dateConfirmed),
              createdAt: now,
              updatedAt: now,
              dirty: const Value(true),
            ),
          );
      await _attachTagsTx(id, tagIds, now);
    });
    _trackTransferCreatedMetric(
      createdBy: createdBy,
      crossCurrency: currency != toCurrency,
    );
    return id;
  }

  /// Records `balanceAfter` and stores the local best-effort delta as the
  /// amount; the recompute pass (and the server) correct the delta when
  /// back-dated rows arrive later.
  Future<String> addBalanceAdjustment({
    required String accountId,
    required BigInt balanceAfterCents,
    required String currency,
    String createdBy = 'form',
    String name = 'Ajuste de saldo',
    String? description,
    BigInt? dateMs,
    bool dateConfirmed = true,
    TransactionTimeStatus timeStatus = TransactionTimeStatus.none,
  }) async {
    final id = newUuid();
    final now = currentMs;
    // Read-then-write in one SQL transaction so a concurrent write can't slip
    // in between the balance read and the insert and make the stored delta
    // inconsistent with the balance it was computed against.
    await db.transaction(() async {
      final currentBalance = await computeAccountBalance(db, accountId);
      final amount = balanceAfterCents - currentBalance;
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: id,
              type: 'balance_adjustment',
              name: name,
              description: Value(description),
              status: 'cleared',
              date: _resolveTransactionDate(
                dateMs: dateMs,
                timeStatus: timeStatus,
                loadedAtMs: now,
              ),
              timeStatus: Value(timeStatus),
              accountId: accountId,
              categoryId: '',
              amount: amount,
              currency: currency,
              balanceAfter: Value(balanceAfterCents),
              dateConfirmed: Value(dateConfirmed),
              createdAt: now,
              updatedAt: now,
              dirty: const Value(true),
            ),
          );
    });
    _trackCreatedMetric(type: 'balance_adjustment', createdBy: createdBy);
    return id;
  }

  void _trackCreatedMetric({required String type, required String createdBy}) {
    _businessMetrics?.movementCreated(movementType: type, createdBy: createdBy);
  }

  void _trackTransferCreatedMetric({
    required String createdBy,
    required bool crossCurrency,
  }) {
    _businessMetrics?.transferCreated(
      createdBy: createdBy,
      crossCurrency: crossCurrency,
    );
  }

  /// Partial update via `Value<T>` (absent = keep). Always bumps `updatedAt`
  /// and re-dirties.
  Future<void> update(
    String id, {
    Value<String> name = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<BigInt> date = const Value.absent(),
    Value<bool> dateConfirmed = const Value.absent(),
    Value<TransactionTimeStatus> timeStatus = const Value.absent(),
    Value<String> accountId = const Value.absent(),
    Value<BigInt> amount = const Value.absent(),
    Value<String> currency = const Value.absent(),
    Value<String> categoryId = const Value.absent(),
    Value<String?> toAccountId = const Value.absent(),
    Value<BigInt?> toAmount = const Value.absent(),
    Value<String?> toCurrency = const Value.absent(),
    Value<double?> exchangeRate = const Value.absent(),
    Value<String> status = const Value.absent(),
  }) async {
    var resolvedDate = date;
    if (date.present) {
      final existing = await getById(id);
      if (existing == null) return;
      resolvedDate = Value(
        _resolveTransactionDate(
          dateMs: date.value,
          timeStatus: timeStatus.present
              ? timeStatus.value
              : existing.timeStatus,
          loadedAtMs: existing.createdAt,
        ),
      );
    }

    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        name: name,
        description: description,
        date: resolvedDate,
        dateConfirmed: dateConfirmed,
        timeStatus: timeStatus,
        accountId: accountId,
        amount: amount,
        currency: currency,
        categoryId: categoryId,
        toAccountId: toAccountId,
        toAmount: toAmount,
        toCurrency: toCurrency,
        exchangeRate: exchangeRate,
        status: status,
        updatedAt: Value(currentMs),
        dirty: const Value(true),
      ),
    );
  }

  /// Soft-deletes a transaction: hard-deletes + tombstones every tag join,
  /// then archives + tombstones the transaction — atomically. The server gets
  /// no join cascade on a transaction tombstone, so the per-join tombstones
  /// are load-bearing. No-op when the transaction does not exist.
  Future<void> delete(String id) async {
    final txn = await getById(id);
    if (txn == null) return;

    final now = currentMs;
    await db.transaction(() async {
      final joins = await (db.select(
        db.transactionTags,
      )..where((j) => j.transactionId.equals(id))).get();
      for (final j in joins) {
        await (db.delete(
          db.transactionTags,
        )..where((t) => t.id.equals(j.id))).go();
        await markDeleted('transactionTags', j.id);
      }

      await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          archived: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await markDeleted('transactions', id);
    });
  }

  /// Attaches [tagIds] to a transaction (idempotent). Returns how many joins
  /// were actually created.
  Future<int> addTags(String transactionId, List<String> tagIds) async {
    final now = currentMs;
    var added = 0;
    await db.transaction(() async {
      added = await _attachTagsTx(transactionId, tagIds, now);
    });
    return added;
  }

  /// Detaches [tagIds] from a transaction (joins hard-deleted + tombstoned).
  /// Returns how many joins were actually removed.
  Future<int> removeTags(String transactionId, List<String> tagIds) async {
    var removed = 0;
    await db.transaction(() async {
      for (final tagId in tagIds) {
        final join =
            await (db.select(db.transactionTags)..where(
                  (j) =>
                      j.transactionId.equals(transactionId) &
                      j.tagId.equals(tagId),
                ))
                .getSingleOrNull();
        if (join == null) continue;
        await (db.delete(
          db.transactionTags,
        )..where((t) => t.id.equals(join.id))).go();
        await markDeleted('transactionTags', join.id);
        removed += 1;
      }
    });
    return removed;
  }

  BigInt _accountDelta(Transaction t, String accountId) {
    var delta = BigInt.zero;
    if (t.accountId == accountId) {
      switch (t.type) {
        case 'expense':
        case 'transfer':
          delta -= t.amount;
          break;
        case 'income':
        case 'balance_adjustment':
          delta += t.amount;
          break;
      }
    }
    if (t.type == 'transfer' && t.toAccountId == accountId) {
      delta += t.toAmount ?? t.amount;
    }
    return delta;
  }

  /// Join ids are deterministic (`txnId__tagId`) so an untag → retag
  /// round-trip recreates the same id with a newer `updatedAt`, letting the
  /// merge drop the older tombstone.
  Future<int> _attachTagsTx(
    String transactionId,
    List<String> tagIds,
    BigInt now,
  ) async {
    var added = 0;
    for (final tagId in tagIds) {
      final existing =
          await (db.select(db.transactionTags)..where(
                (j) =>
                    j.transactionId.equals(transactionId) &
                    j.tagId.equals(tagId),
              ))
              .getSingleOrNull();
      if (existing != null) continue;
      await db
          .into(db.transactionTags)
          .insert(
            TransactionTagsCompanion.insert(
              id: '${transactionId}__$tagId',
              transactionId: transactionId,
              tagId: tagId,
              createdAt: now,
              updatedAt: now,
              dirty: const Value(true),
            ),
          );
      added += 1;
    }
    return added;
  }
}

BigInt _resolveTransactionDate({
  required BigInt? dateMs,
  required TransactionTimeStatus timeStatus,
  required BigInt loadedAtMs,
}) {
  if (timeStatus != TransactionTimeStatus.none) {
    if (dateMs == null) {
      throw ArgumentError('A date with a time is required for $timeStatus');
    }
    return dateMs;
  }

  if (dateMs == null) return loadedAtMs;

  final selectedDate = DateTime.fromMillisecondsSinceEpoch(dateMs.toInt());
  final loadedAt = DateTime.fromMillisecondsSinceEpoch(loadedAtMs.toInt());
  return BigInt.from(
    DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      loadedAt.hour,
      loadedAt.minute,
      loadedAt.second,
      loadedAt.millisecond,
    ).millisecondsSinceEpoch,
  );
}

class AccountBalanceAroundTransaction {
  const AccountBalanceAroundTransaction({
    required this.before,
    required this.after,
  });

  final BigInt before;
  final BigInt after;
}
