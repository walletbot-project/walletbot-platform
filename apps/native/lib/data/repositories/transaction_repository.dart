import 'package:drift/drift.dart';

import '../../database.dart';
import '../../telemetry/business_metrics.dart';
import '../balance_adjustments.dart';
import '../ids.dart';
import '../models/recurrence_series.dart';
import '../models/transaction_filter.dart';
import '../occurrence.dart';
import '../recurrence.dart';
import '../queries/stream_utils.dart';
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

  /// The other side of the occurrence cutoff: the movements that exist but
  /// have not happened yet, soonest first. Ordinary transactions — the only
  /// thing that sets them apart is which side of the cutoff their date is on.
  Stream<List<Transaction>> watchUpcoming({int? limit}) =>
      watchFilteredTransactions(
        db,
        const TransactionFilter(),
        limit: limit,
        ordering: TxnOrdering.dateAsc,
        occurrence: TxnOccurrence.upcoming,
      );

  /// The rule a movement belongs to and how far its series reaches, or `null`
  /// when the movement is a one-off (or the rule has since been deleted — the
  /// movement itself stays perfectly valid).
  ///
  /// Reactive to the series growing, so a top-up updates the reach shown in
  /// the detail without the screen having to ask again.
  Stream<RecurrenceSeries?> watchSeries(
    String? recurrenceId, {
    int? occurrenceIndex,
  }) {
    if (recurrenceId == null) return Stream.value(null);
    return combineLatest2(
      _ruleQuery(recurrenceId).watchSingleOrNull(),
      _seriesSlotsQuery(recurrenceId).watch(),
      (Recurrence? rule, List<Transaction> slots) =>
          _series(rule, slots, occurrenceIndex),
    );
  }

  /// One-shot [watchSeries], for the screens that load their detail once
  /// rather than subscribing (the Activity detail's `Future.wait`).
  Future<RecurrenceSeries?> seriesOf(
    String? recurrenceId, {
    int? occurrenceIndex,
  }) async {
    if (recurrenceId == null) return null;
    final rule = await _ruleQuery(recurrenceId).getSingleOrNull();
    final slots = await _seriesSlotsQuery(recurrenceId).get();
    return _series(rule, slots, occurrenceIndex);
  }

  SimpleSelectStatement<$RecurrencesTable, Recurrence> _ruleQuery(String id) =>
      db.select(db.recurrences)
        ..where((r) => r.id.equals(id) & r.archived.equals(false));

  /// The series newest-slot-first, one row past [seriesCountCap] so "did it
  /// fit?" is answerable.
  ///
  /// Archived slots come back too and are filtered in Dart: that keeps the
  /// read exactly `seriesCountCap + 1` rows instead of however many deleted
  /// ones a filtered query would have had to walk past.
  SimpleSelectStatement<$TransactionsTable, Transaction> _seriesSlotsQuery(
    String recurrenceId,
  ) => db.select(db.transactions)
    ..where((t) => t.recurrenceId.equals(recurrenceId))
    ..orderBy([(t) => OrderingTerm.desc(t.recurrenceIndex)])
    ..limit(seriesCountCap + 1);

  RecurrenceSeries? _series(
    Recurrence? rule,
    List<Transaction> slots,
    int? occurrenceIndex,
  ) {
    if (rule == null) return null;
    final counted = slots.length <= seriesCountCap;
    final living = slots.where((t) => !t.archived).toList(growable: false);
    return RecurrenceSeries(
      rule: rule,
      position: counted && occurrenceIndex != null
          ? living
                .where((t) => (t.recurrenceIndex ?? 0) <= occurrenceIndex)
                .length
          : null,
      total: counted ? living.length : null,
      coveredThrough: living.isEmpty
          ? null
          : DateTime.fromMillisecondsSinceEpoch(living.first.date.toInt()),
    );
  }

  /// One-shot [watchUpcoming], for the agent tool.
  Future<List<Transaction>> listUpcoming({int? limit}) => list(
    const TransactionFilter(),
    limit: limit,
    ordering: TxnOrdering.dateAsc,
    occurrence: TxnOccurrence.upcoming,
  );

  /// The user's live recurring rules, each with the movement it creates and
  /// how far its series reaches — what the agent needs to answer "what do I
  /// have repeating?" and to address a rule by name.
  Future<
    List<({Recurrence rule, Transaction? anchor, DateTime? coveredThrough})>
  >
  listRecurrences({int limit = 50}) async {
    final rules =
        await (db.select(db.recurrences)
              ..where((r) => r.archived.equals(false))
              ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
              ..limit(limit))
            .get();
    final out =
        <({Recurrence rule, Transaction? anchor, DateTime? coveredThrough})>[];
    for (final rule in rules) {
      final anchor =
          await (db.select(db.transactions)..where(
                (t) =>
                    t.recurrenceId.equals(rule.id) &
                    t.recurrenceIndex.equals(0),
              ))
              .getSingleOrNull();
      final last = await _lastOccurrenceOf(rule.id);
      out.add((
        rule: rule,
        anchor: anchor,
        coveredThrough: last == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(last.date.toInt()),
      ));
    }
    return out;
  }

  Future<Transaction?> _lastOccurrenceOf(String recurrenceId) =>
      (db.select(db.transactions)
            ..where((t) => t.recurrenceId.equals(recurrenceId))
            ..orderBy([(t) => OrderingTerm.desc(t.recurrenceIndex)])
            ..limit(1))
          .getSingleOrNull();

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
    TxnOccurrence occurrence = TxnOccurrence.occurred,
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
      occurrence: occurrence,
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
  /// immediately before and after [transactionId], in ledger order.
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

    // Ledger order — the same one a balance adjustment is derived in, so the
    // "before" next to an adjustment is exactly what it was measured against.
    final entries = rows.map(LedgerEntry.fromTransaction).toList()
      ..sort(compareLedgerOrder);

    var running = BigInt.zero;
    for (final entry in entries) {
      final before = running;
      running += ledgerDelta(entry, accountId);
      if (entry.id == transactionId) {
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
    RecurrenceDraft? recurrence,
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
    recurrence: recurrence,
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
    RecurrenceDraft? recurrence,
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
    recurrence: recurrence,
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
    RecurrenceDraft? recurrence,
  }) async {
    final id = newUuid();
    final now = currentMs;
    final date = _resolveTransactionDate(
      dateMs: dateMs,
      timeStatus: timeStatus,
      loadedAtMs: now,
    );
    final recurrenceId = recurrence == null ? null : newUuid();
    final anchor = DateTime.fromMillisecondsSinceEpoch(date.toInt());
    if (recurrence != null) {
      final total = occurrenceCount(
        anchor,
        recurrence.frequency,
        recurrence.endDate,
        dayInterval: recurrence.dayInterval,
      );
      final max = maxOccurrenceCount(
        recurrence.frequency,
        dayInterval: recurrence.dayInterval,
      );
      if (total > max) {
        throw ArgumentError(
          'Recurrence would create $total movements; the maximum is $max',
        );
      }
    }
    await db.transaction(() async {
      if (recurrence != null && recurrenceId != null) {
        await db
            .into(db.recurrences)
            .insert(
              RecurrencesCompanion.insert(
                id: recurrenceId,
                frequency: recurrence.frequency.name,
                dayInterval:
                    recurrence.frequency == RecurrenceFrequency.customDays
                    ? Value(recurrence.dayInterval)
                    : const Value.absent(),
                anchorDate: date,
                endDate: recurrence.endDate != null
                    ? Value(
                        BigInt.from(recurrence.endDate!.millisecondsSinceEpoch),
                      )
                    : const Value.absent(),
                createdAt: now,
                updatedAt: now,
                dirty: const Value(true),
              ),
            );
      }
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: id,
              recurrenceId: recurrenceId != null
                  ? Value(recurrenceId)
                  : const Value.absent(),
              recurrenceIndex: recurrenceId != null
                  ? const Value(0)
                  : const Value.absent(),
              type: type,
              name: name,
              description: Value(description),
              status: status,
              date: date,
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

      // The rest of the series. Unlike the web — where a workflow materialises
      // these server-side — native writes them locally: a movement created
      // offline has to exist offline. They sync up like any other row, and the
      // backend never regenerates a series it received, so the two paths
      // cannot double up.
      if (recurrence != null && recurrenceId != null) {
        final total = occurrenceCount(
          anchor,
          recurrence.frequency,
          recurrence.endDate,
          dayInterval: recurrence.dayInterval,
        );
        for (var index = 1; index < total; index++) {
          final occurrence = occurrenceDate(
            anchor,
            recurrence.frequency,
            index,
            dayInterval: recurrence.dayInterval,
          );
          await db
              .into(db.transactions)
              .insert(
                TransactionsCompanion.insert(
                  id: newUuid(),
                  recurrenceId: Value(recurrenceId),
                  recurrenceIndex: Value(index),
                  type: type,
                  name: name,
                  description: Value(description),
                  status: status,
                  date: BigInt.from(occurrence.millisecondsSinceEpoch),
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
        }
      }
      await _reconcileAdjustments({accountId});
    });
    _trackCreatedMetric(type: type, createdBy: createdBy);
    return id;
  }

  /// Tops a rule up by another batch: the same N it was created with
  /// ([recurrenceHorizon]), continuing from the **last occurrence that
  /// exists**. Returns how many were created.
  ///
  /// Not from the occurrence the user was looking at when they asked. Opening
  /// September's movement of a series already materialised through November
  /// and asking for 48 more has to mean December onwards — anything else would
  /// either collide with the movements already there or leave a hole.
  ///
  /// Only for open-ended rules: a rule with an end date is already complete,
  /// and running past a boundary the user set on purpose is editing the rule,
  /// not extending it. Returns 0 when there is nothing to extend.
  ///
  /// Written locally, like the initial batch — a movement created offline has
  /// to exist offline. The rows sync up as ordinary transactions and the
  /// backend never regenerates a series it received, so the two paths cannot
  /// double up.
  Future<int> addOccurrences(String recurrenceId) async {
    final rule =
        await (db.select(db.recurrences)..where(
              (r) => r.id.equals(recurrenceId) & r.archived.equals(false),
            ))
            .getSingleOrNull();
    if (rule == null || rule.endDate != null) return 0;

    final frequency = recurrenceFrequencyFromName(rule.frequency);
    if (frequency == null) return 0;
    final dayInterval = rule.dayInterval ?? 1;
    final anchor = DateTime.fromMillisecondsSinceEpoch(rule.anchorDate.toInt());

    // The highest occurrence index says where to continue *from*. By index,
    // not by date: once a single occurrence's date can be edited the two stop
    // agreeing, and it is the index that says which slots are taken.
    final last =
        await (db.select(db.transactions)
              ..where((t) => t.recurrenceId.equals(recurrenceId))
              ..orderBy([(t) => OrderingTerm.desc(t.recurrenceIndex)])
              ..limit(1))
            .getSingleOrNull();
    if (last == null || last.recurrenceIndex == null) return 0;

    // What the new movements *look like* comes from occurrence 0, though, not
    // from the last one: the anchor is the rule's shape. Copying the last
    // occurrence would let a single edited movement silently redefine the
    // whole future series, which is precisely the choice "this one" vs "this
    // one and the ones after it" exists to make explicit.
    final anchorRow =
        await (db.select(db.transactions)..where(
              (t) =>
                  t.recurrenceId.equals(recurrenceId) &
                  t.recurrenceIndex.equals(0),
            ))
            .getSingleOrNull();
    if (anchorRow == null) return 0;

    final count = recurrenceHorizon(frequency, dayInterval: dayInterval).count;
    final from = last.recurrenceIndex! + 1;
    final now = currentMs;

    await db.transaction(() async {
      for (var index = from; index < from + count; index++) {
        final occurrence = occurrenceDate(
          anchor,
          frequency,
          index,
          dayInterval: dayInterval,
        );
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: newUuid(),
                recurrenceId: Value(recurrenceId),
                recurrenceIndex: Value(index),
                type: anchorRow.type,
                name: anchorRow.name,
                description: Value(anchorRow.description),
                status: anchorRow.status,
                date: BigInt.from(occurrence.millisecondsSinceEpoch),
                timeStatus: Value(anchorRow.timeStatus),
                accountId: anchorRow.accountId,
                categoryId: anchorRow.categoryId,
                amount: anchorRow.amount,
                currency: anchorRow.currency,
                dateConfirmed: Value(anchorRow.dateConfirmed),
                createdAt: now,
                updatedAt: now,
                dirty: const Value(true),
              ),
            );
      }
      await _reconcileAdjustments(_accountsOf([anchorRow]));
    });
    return count;
  }

  // ───── "This one and the ones after it" ─────

  /// The occurrence a scoped edit or delete starts from, with its rule. Null
  /// when the movement is a one-off or its rule is gone.
  Future<({Transaction row, Recurrence rule, int index})?> _occurrenceOf(
    String transactionId,
  ) async {
    final row = await getById(transactionId);
    final recurrenceId = row?.recurrenceId;
    final index = row?.recurrenceIndex;
    if (row == null || recurrenceId == null || index == null) return null;
    final rule = await _ruleQuery(recurrenceId).getSingleOrNull();
    if (rule == null) return null;
    return (row: row, rule: rule, index: index);
  }

  /// Truncates a rule so it stops claiming the occurrences from [index] on.
  ///
  /// The end date is what `X/N` and the top-up button read, so leaving it
  /// pointing past a tail that no longer exists would have the detail describe
  /// a series longer than the one on screen. At index 0 there is no previous
  /// occurrence to end on, so the rule itself goes.
  Future<void> _truncateRuleBeforeTx(
    Recurrence rule,
    int index,
    BigInt now,
  ) async {
    if (index == 0) {
      await (db.update(
        db.recurrences,
      )..where((r) => r.id.equals(rule.id))).write(
        RecurrencesCompanion(
          archived: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await markDeleted('recurrences', rule.id);
      return;
    }
    final previous =
        await (db.select(db.transactions)..where(
              (t) =>
                  t.recurrenceId.equals(rule.id) &
                  t.recurrenceIndex.equals(index - 1),
            ))
            .getSingleOrNull();
    if (previous == null) return;
    await (db.update(db.recurrences)..where((r) => r.id.equals(rule.id))).write(
      RecurrencesCompanion(
        endDate: Value(previous.date),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
  }

  /// Deletes this occurrence and every later one, and truncates the rule.
  /// Returns how many were archived. No-op for a one-off movement.
  Future<int> deleteFuture(String transactionId) async {
    final found = await _occurrenceOf(transactionId);
    // No series: "this one and the ones after it" has nothing after it, so it
    // means this one. Degrading beats returning 0 and letting the caller
    // report a delete that never happened.
    if (found == null) {
      await delete(transactionId);
      return 1;
    }

    final tail =
        await (db.select(db.transactions)
              ..where(
                (t) =>
                    t.recurrenceId.equals(found.rule.id) &
                    t.recurrenceIndex.isBiggerOrEqualValue(found.index) &
                    t.archived.equals(false),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.recurrenceIndex)]))
            .get();

    final now = currentMs;
    await db.transaction(() async {
      // Truncate first, while occurrence `index - 1` is still the last one
      // standing — after the tail goes, its date is what the rule ends on.
      await _truncateRuleBeforeTx(found.rule, found.index, now);
      for (final row in tail) {
        await _deleteTx(row.id, now);
      }
      await _reconcileAdjustments(_accountsOf(tail));
    });
    return tail.length;
  }

  /// Carries an edit to this occurrence and every later one. Returns how many
  /// were changed.
  ///
  /// Only the value fields. A change of cadence or of the anchor date is a
  /// [splitSeries], not this: the occurrences before this one keep their own
  /// spacing, so "from here on, weekly" describes two rules, not one.
  Future<int> updateFuture(
    String transactionId, {
    Value<String> name = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<BigInt> amount = const Value.absent(),
    Value<String> accountId = const Value.absent(),
    Value<String> currency = const Value.absent(),
    Value<String> categoryId = const Value.absent(),
  }) async {
    final found = await _occurrenceOf(transactionId);
    // No series: the edit applies to this movement and that is all of them.
    if (found == null) {
      await update(
        transactionId,
        name: name,
        description: description,
        amount: amount,
        accountId: accountId,
        currency: currency,
        categoryId: categoryId,
      );
      return 1;
    }

    final now = currentMs;
    Expression<bool> inTail($TransactionsTable t) =>
        t.recurrenceId.equals(found.rule.id) &
        t.recurrenceIndex.isBiggerOrEqualValue(found.index) &
        t.archived.equals(false);
    return db.transaction(() async {
      // The accounts the tail sits on before the edit, too: moving it to
      // another account changes the adjustments it leaves behind.
      final before = await (db.select(db.transactions)..where(inTail)).get();
      // One statement for the whole tail: unlike the delete, a value edit
      // needs no per-row tombstone or join cascade, so there is nothing to
      // loop over.
      final changed = await (db.update(db.transactions)..where(inTail)).write(
        TransactionsCompanion(
          name: name,
          description: description,
          amount: amount,
          accountId: accountId,
          currency: currency,
          categoryId: categoryId,
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await _reconcileAdjustments({
        ..._accountsOf(before),
        if (accountId.present) accountId.value,
      });
      return changed;
    });
  }

  /// Re-cadences a series from this occurrence on, by splitting it in two.
  ///
  /// There is no way to express "from here on, weekly" as one rule: every
  /// occurrence is projected from the anchor by index
  /// (`docs/recurrency-design.md` §2.3), so changing the cadence would move
  /// the occurrences *before* this one too. What the user means is two rules —
  /// the original ending where they stopped it, and a new one starting here.
  ///
  /// Built out of the two operations that already exist: the old tail is
  /// deleted and a new series is created at [date]. The new rule inherits the
  /// old one's end date, because the user moved the cadence, not the end.
  /// Returns the new anchor's id, or null for a one-off movement.
  Future<String?> splitSeries(
    String transactionId, {
    required RecurrenceFrequency frequency,
    required int dayInterval,
    required BigInt date,
    required bool dateConfirmed,
    required TransactionTimeStatus timeStatus,
    required String name,
    required String? description,
    required BigInt amountCents,
    required String accountId,
    required String currency,
    required String categoryId,
  }) async {
    final found = await _occurrenceOf(transactionId);
    if (found == null) return null;

    final endDate = found.rule.endDate;
    // One transaction over both halves — drift nests these as savepoints. A
    // split that only got as far as deleting the old tail would leave the
    // user with neither series.
    return db.transaction(() async {
      await deleteFuture(transactionId);
      return _addSimple(
        type: found.row.type,
        accountId: accountId,
        categoryId: categoryId,
        name: name,
        amountCents: amountCents,
        currency: currency,
        description: description,
        status: found.row.status,
        dateMs: date,
        dateConfirmed: dateConfirmed,
        timeStatus: timeStatus,
        tagIds: const [],
        createdBy: 'form',
        recurrence: RecurrenceDraft(
          frequency: frequency,
          dayInterval: dayInterval,
          endDate: endDate == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(endDate.toInt()),
        ),
      );
    });
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
      await _reconcileAdjustments({fromAccountId, toAccountId});
    });
    _trackTransferCreatedMetric(
      createdBy: createdBy,
      crossCurrency: currency != toCurrency,
    );
    return id;
  }

  /// Records the declaration `balanceAfter` and derives the amount from the
  /// ledger just before the adjustment's own date. Later writes before it —
  /// local, or merged by sync — re-derive the amount, so the declaration keeps
  /// holding (`lib/data/balance_adjustments.dart`).
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
    final date = _resolveTransactionDate(
      dateMs: dateMs,
      timeStatus: timeStatus,
      loadedAtMs: now,
    );
    // Read-then-write in one SQL transaction so a concurrent write can't slip
    // in between the balance read and the insert and make the stored delta
    // inconsistent with the balance it was computed against.
    await db.transaction(() async {
      final previousBalance = await localBalanceBeforeInLedger(
        db,
        accountId,
        LedgerEntry(
          id: id,
          type: 'balance_adjustment',
          accountId: accountId,
          amount: BigInt.zero,
          balanceAfter: balanceAfterCents,
          date: date,
          createdAt: now,
        ),
      );
      final amount = balanceAfterCents - previousBalance;
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: id,
              type: 'balance_adjustment',
              name: name,
              description: Value(description),
              status: 'cleared',
              date: date,
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
      // The declaration pins the balance after it, so the next adjustment
      // on the account now starts from it.
      await _reconcileAdjustments({accountId});
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
  /// and re-dirties. No-op when the transaction does not exist.
  ///
  /// A balance adjustment's amount is derived from the ledger and its date and
  /// account are where the declaration was made, so changing any of them
  /// throws [ArgumentError].
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
    final existing = await getById(id);
    if (existing == null) return;
    if (existing.type == 'balance_adjustment') {
      if (amount.present) {
        throw ArgumentError('Balance adjustment amount cannot be changed');
      }
      if (date.present || dateConfirmed.present || timeStatus.present) {
        throw ArgumentError('Balance adjustment date cannot be changed');
      }
      if (accountId.present && accountId.value != existing.accountId) {
        throw ArgumentError('Balance adjustment account cannot be changed');
      }
    }

    var resolvedDate = date;
    if (date.present) {
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

    await db.transaction(() async {
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
      // Both where it was and where it is now: a move between accounts, or
      // across an adjustment's date, changes the adjustments on both sides.
      await _reconcileAdjustments({
        ..._accountsOf([existing]),
        if (accountId.present) accountId.value,
        if (toAccountId.present && toAccountId.value != null)
          toAccountId.value!,
      });
    });
  }

  /// Soft-deletes a transaction: hard-deletes + tombstones every tag join,
  /// then archives + tombstones the transaction — atomically. The server gets
  /// no join cascade on a transaction tombstone, so the per-join tombstones
  /// are load-bearing. No-op when the transaction does not exist.
  Future<void> delete(String id) async {
    final txn = await getById(id);
    if (txn == null) return;
    await db.transaction(() async {
      await _deleteTx(id, currentMs);
      await _reconcileAdjustments(_accountsOf([txn]));
    });
  }

  /// The body of [delete], without its transaction, so a scoped delete can
  /// archive a whole tail atomically. Every occurrence has to end up in
  /// exactly the state deleting it on its own would — the per-join tombstones
  /// included, since the server gets no cascade from a transaction tombstone.
  Future<void> _deleteTx(String id, BigInt now) async {
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

  /// The accounts whose balance [rows] move.
  Set<String> _accountsOf(Iterable<Transaction> rows) => {
    for (final row in rows) ...[
      row.accountId,
      if (row.type == 'transfer' && row.toAccountId != null) row.toAccountId!,
    ],
  };

  /// Re-derives the balance adjustments on [accountIds] after a write moved
  /// what came before them. Call inside the write's own `db.transaction`.
  Future<void> _reconcileAdjustments(Set<String> accountIds) =>
      reconcileLocalAdjustments(db, accountIds: accountIds);

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
