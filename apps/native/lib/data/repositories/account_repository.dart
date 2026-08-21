import 'package:drift/drift.dart';

import '../../database.dart';
import '../../telemetry/business_metrics.dart';
import '../ids.dart';
import '../queries/account_balance.dart';
import 'repository_base.dart';

/// Thrown by [AccountRepository.create]/[AccountRepository.update] when the
/// resulting name+currency would collide with another active account.
class DuplicateAccountException implements Exception {
  const DuplicateAccountException();

  @override
  String toString() => 'Account with that name and currency already exists';
}

String _normalizeAccountName(String value) => value.trim().toLowerCase();

/// Reads and writes for wallet accounts (the user's cash/bank/card pockets,
/// not auth accounts).
class AccountRepository extends RepositoryBase {
  AccountRepository(super.db, {BusinessMetrics? businessMetrics})
    : _businessMetrics = businessMetrics;

  final BusinessMetrics? _businessMetrics;

  /// Active accounts ordered by creation time (the accounts screen order).
  Stream<List<Account>> watchActive() =>
      (db.select(db.accounts)
            ..where((a) => a.archived.equals(false))
            ..orderBy([(a) => OrderingTerm(expression: a.createdAt)]))
          .watch();

  /// Live list, active-only by default. Insertion order.
  Stream<List<Account>> watchAll({bool includeArchived = false}) {
    final query = db.select(db.accounts);
    if (!includeArchived) {
      query.where((a) => a.archived.equals(false));
    }
    return query.watch();
  }

  /// One-shot list, active-only by default. Insertion order, no sorting.
  Future<List<Account>> listAll({bool includeArchived = false}) {
    final query = db.select(db.accounts);
    if (!includeArchived) {
      query.where((a) => a.archived.equals(false));
    }
    return query.get();
  }

  /// Alias of [listAll] with the default scope, for readable call sites.
  Future<List<Account>> listActive() => listAll();

  /// Exact-id lookup; finds archived accounts too. Null when missing.
  Future<Account?> getById(String id) =>
      (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingleOrNull();

  /// Current balance in cents (see `queries/account_balance.dart` for the
  /// arithmetic, which must stay in lockstep with the sync recompute).
  Future<BigInt> getBalanceCents(String accountId) =>
      computeAccountBalance(db, accountId);

  /// Live balance: re-emits whenever any transaction touching the account
  /// changes (local writes, agent writes, or sync merges).
  Stream<BigInt> watchBalanceCents(String accountId) =>
      watchAccountBalance(db, accountId);

  /// Live total balance across all active accounts in [currency], for the
  /// dashboard Balance card.
  Stream<BigInt> watchBalanceForCurrency(String currency) =>
      watchTotalBalanceForCurrency(db, currency);

  /// Throws [DuplicateAccountException] when an active account with the
  /// same [currency] and a name equal to [name] (trim + case-insensitive)
  /// already exists, other than [excludeId] itself.
  Future<void> _assertNoDuplicate({
    required String currency,
    required String name,
    String? excludeId,
  }) async {
    final normalized = _normalizeAccountName(name);
    final sameCurrency =
        await (db.select(db.accounts)..where(
              (a) => a.archived.equals(false) & a.currency.equals(currency),
            ))
            .get();
    final hasDuplicate = sameCurrency.any(
      (a) => a.id != excludeId && _normalizeAccountName(a.name) == normalized,
    );
    if (hasDuplicate) throw const DuplicateAccountException();
  }

  /// Creates an account, optionally with an initial-balance adjustment
  /// (`Balance inicial`), atomically. Returns the new account id.
  Future<String> create({
    required String name,
    required String currency,
    String createdBy = 'form',
    String? description,
    String? color,
    String? icon,
    BigInt? initialBalanceCents,
  }) async {
    await _assertNoDuplicate(currency: currency, name: name);
    final id = newUuid();
    final now = currentMs;
    await db.transaction(() async {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: id,
              name: name,
              currency: currency,
              description: Value(description),
              color: Value.absentIfNull(color),
              icon: Value.absentIfNull(icon),
              createdAt: now,
              updatedAt: now,
              dirty: const Value(true),
            ),
          );
      if (initialBalanceCents != null) {
        // Account is brand new, so the delta from zero IS the target balance.
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: newUuid(),
                type: 'balance_adjustment',
                name: 'Balance inicial',
                status: 'cleared',
                date: now,
                accountId: id,
                categoryId: '',
                amount: initialBalanceCents,
                currency: currency,
                balanceAfter: Value(initialBalanceCents),
                createdAt: now,
                updatedAt: now,
                dirty: const Value(true),
              ),
            );
      }
    });
    _businessMetrics?.financialAccountCreated(createdBy: createdBy);
    if (initialBalanceCents != null) {
      _businessMetrics?.movementCreated(
        movementType: 'balance_adjustment',
        createdBy: createdBy,
      );
    }
    return id;
  }

  /// Partial update: pass `Value(x)` to set a field (including `Value(null)`
  /// to clear a nullable one) and leave it `Value.absent()` to keep it.
  /// Always bumps `updatedAt` and re-dirties, even with no field changes.
  Future<void> update(
    String id, {
    Value<String> name = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<String> color = const Value.absent(),
    Value<String> icon = const Value.absent(),
  }) async {
    if (name.present) {
      final current = await getById(id);
      if (current != null) {
        await _assertNoDuplicate(
          currency: current.currency,
          name: name.value,
          excludeId: id,
        );
      }
    }
    await (db.update(db.accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(
        name: name,
        description: description,
        color: color,
        icon: icon,
        updatedAt: Value(currentMs),
        dirty: const Value(true),
      ),
    );
  }

  /// Soft delete: `archived = true` + tombstone, atomically. The row stays
  /// in the local database; other devices hard-delete it when the tombstone
  /// syncs.
  Future<void> archive(String id) async {
    final now = currentMs;
    await db.transaction(() async {
      await (db.update(db.accounts)..where((a) => a.id.equals(id))).write(
        AccountsCompanion(
          archived: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await markDeleted('accounts', id);
    });
  }
}
