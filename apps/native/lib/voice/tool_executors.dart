import 'dart:math';

import 'package:drift/drift.dart';

import '../database.dart';
import 'tool_parsing.dart';

// Native tool executors. All operations run against the local Drift database;
// the sync layer pushes dirty rows to Convex. NEVER call the Convex backend
// directly from here — native must work offline.

class ToolExecutors {
  ToolExecutors(this.db);

  final AppDatabase db;

  Future<Map<String, dynamic>> execute(String name, Map<String, dynamic> args) async {
    try {
      switch (name) {
        // Accounts
        case 'listAccounts':
          return await _listAccounts(args);
        case 'getAccount':
          return await _getAccount(args);
        case 'getAccountBalance':
          return await _getAccountBalance(args);
        case 'createAccount':
          return await _createAccount(args);
        case 'updateAccount':
          return await _updateAccount(args);
        case 'archiveAccount':
          return await _archiveAccount(args);
        // Categories
        case 'listCategories':
          return await _listCategories(args);
        case 'getCategory':
          return await _getCategory(args);
        case 'createCategory':
          return await _createCategory(args);
        case 'updateCategory':
          return await _updateCategory(args);
        case 'archiveCategory':
          return await _archiveCategory(args);
        // Tags
        case 'listTags':
          return await _listTags(args);
        case 'getTag':
          return await _getTag(args);
        case 'createTag':
          return await _createTag(args);
        case 'updateTag':
          return await _updateTag(args);
        case 'archiveTag':
          return await _archiveTag(args);
        // Transactions: read
        case 'listTransactions':
          return await _listTransactions(args);
        case 'getTransaction':
          return await _getTransaction(args);
        case 'getRecentTransactions':
          return await _getRecentTransactions(args);
        // Transactions: write
        case 'addExpense':
          return await _addExpense(args);
        case 'addIncome':
          return await _addIncome(args);
        case 'addTransfer':
          return await _addTransfer(args);
        case 'addBalanceAdjustment':
          return await _addBalanceAdjustment(args);
        case 'updateTransaction':
          return await _updateTransaction(args);
        case 'deleteTransaction':
          return await _deleteTransaction(args);
        case 'tagTransaction':
          return await _tagTransaction(args);
        case 'untagTransaction':
          return await _untagTransaction(args);
        // Summaries
        case 'summarizeByCategory':
          return await _summarizeByCategory(args);
        case 'summarizeByAccount':
          return await _summarizeByAccount(args);
        default:
          return {'ok': false, 'error': 'Unknown tool: $name'};
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  // ───── Resolvers ─────

  Future<Account?> _resolveAccount(String idOrName) async {
    final byId = await (db.select(db.accounts)..where((t) => t.id.equals(idOrName))).getSingleOrNull();
    if (byId != null) return byId;

    final target = normalizeName(idOrName);
    final candidates = await (db.select(db.accounts)..where((t) => t.archived.equals(false))).get();
    final matches = candidates.where((a) => normalizeName(a.name) == target).toList();
    if (matches.length == 1) return matches.first;
    return null;
  }

  Future<List<Account>> _resolveAccountCandidates(String idOrName) async {
    final target = normalizeName(idOrName);
    final candidates = await (db.select(db.accounts)..where((t) => t.archived.equals(false))).get();
    return candidates.where((a) => normalizeName(a.name) == target).toList();
  }

  Future<Category?> _resolveCategory(String idOrName) async {
    final byId = await (db.select(db.categories)..where((t) => t.id.equals(idOrName))).getSingleOrNull();
    if (byId != null) return byId;

    final target = normalizeName(idOrName);
    final candidates = await (db.select(db.categories)..where((t) => t.archived.equals(false))).get();
    final matches = candidates.where((c) => normalizeName(c.name) == target).toList();
    if (matches.length == 1) return matches.first;
    return null;
  }

  Future<List<Category>> _resolveCategoryCandidates(String idOrName) async {
    final target = normalizeName(idOrName);
    final candidates = await (db.select(db.categories)..where((t) => t.archived.equals(false))).get();
    return candidates.where((c) => normalizeName(c.name) == target).toList();
  }

  Future<Tag?> _resolveTag(String idOrName) async {
    final byId = await (db.select(db.tags)..where((t) => t.id.equals(idOrName))).getSingleOrNull();
    if (byId != null) return byId;

    final target = normalizeName(idOrName);
    final candidates = await (db.select(db.tags)..where((t) => t.archived.equals(false))).get();
    final matches = candidates.where((t) => normalizeName(t.name) == target).toList();
    if (matches.length == 1) return matches.first;
    return null;
  }

  Map<String, dynamic> _ambiguous(String label, List<({String id, String name})> candidates) {
    return {
      'ok': false,
      'error': '$label is ambiguous',
      'candidates': candidates.map((c) => {'id': c.id, 'name': c.name}).toList(),
    };
  }

  // ───── Account tools ─────

  Future<Map<String, dynamic>> _listAccounts(Map<String, dynamic> args) async {
    final includeArchived = args['includeArchived'] == true;
    final query = db.select(db.accounts);
    if (!includeArchived) {
      query.where((t) => t.archived.equals(false));
    }
    final rows = await query.get();
    return {
      'ok': true,
      'accounts': rows
          .map((a) => {'id': a.id, 'name': a.name, 'currency': a.currency, 'color': a.color, 'icon': a.icon, 'isArchived': a.archived})
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _getAccount(Map<String, dynamic> args) async {
    final idOrName = args['idOrName'] as String;
    final acc = await _resolveAccount(idOrName);
    if (acc == null) {
      final cands = await _resolveAccountCandidates(idOrName);
      if (cands.length > 1) {
        return _ambiguous('Account', cands.map((c) => (id: c.id, name: c.name)).toList());
      }
      return {'ok': false, 'error': 'Account not found'};
    }
    return {
      'ok': true,
      'account': {'id': acc.id, 'name': acc.name, 'currency': acc.currency, 'color': acc.color, 'icon': acc.icon},
    };
  }

  Future<Map<String, dynamic>> _getAccountBalance(Map<String, dynamic> args) async {
    final acc = await _resolveAccount(args['idOrName'] as String);
    if (acc == null) return {'ok': false, 'error': 'Account not found'};
    final balance = await _computeAccountBalance(acc.id);
    return {'ok': true, 'accountId': acc.id, 'accountName': acc.name, 'balance': balance.toDouble() / 100, 'currency': acc.currency};
  }

  Future<Map<String, dynamic>> _createAccount(Map<String, dynamic> args) async {
    final id = _newUuid();
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: id,
            name: args['name'] as String,
            currency: args['currency'] as String,
            description: Value(args['description'] as String?),
            color: Value(args['color'] as String?),
            icon: Value(args['icon'] as String?),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _updateAccount(Map<String, dynamic> args) async {
    final acc = await _resolveAccount(args['idOrName'] as String);
    if (acc == null) return {'ok': false, 'error': 'Account not found'};

    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await (db.update(db.accounts)..where((t) => t.id.equals(acc.id))).write(
      AccountsCompanion(
        name: args.containsKey('name') ? Value(args['name'] as String) : const Value.absent(),
        description: args.containsKey('description') ? Value(args['description'] as String?) : const Value.absent(),
        color: args.containsKey('color') ? Value(args['color'] as String?) : const Value.absent(),
        icon: args.containsKey('icon') ? Value(args['icon'] as String?) : const Value.absent(),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
    return {'ok': true, 'id': acc.id};
  }

  Future<Map<String, dynamic>> _archiveAccount(Map<String, dynamic> args) async {
    final acc = await _resolveAccount(args['idOrName'] as String);
    if (acc == null) return {'ok': false, 'error': 'Account not found'};

    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await (db.update(db.accounts)..where((t) => t.id.equals(acc.id))).write(
      AccountsCompanion(archived: const Value(true), updatedAt: Value(now), dirty: const Value(true)),
    );
    await _writeTombstone('accounts', acc.id);
    return {'ok': true, 'id': acc.id};
  }

  // ───── Category tools ─────

  Future<Map<String, dynamic>> _listCategories(Map<String, dynamic> args) async {
    final includeArchived = args['includeArchived'] == true;
    final query = db.select(db.categories);
    if (!includeArchived) {
      query.where((t) => t.archived.equals(false));
    }
    final rows = await query.get();
    return {
      'ok': true,
      'categories': rows.map((c) => {'id': c.id, 'name': c.name, 'description': c.description}).toList(),
    };
  }

  Future<Map<String, dynamic>> _getCategory(Map<String, dynamic> args) async {
    final cat = await _resolveCategory(args['idOrName'] as String);
    if (cat == null) {
      final cands = await _resolveCategoryCandidates(args['idOrName'] as String);
      if (cands.length > 1) {
        return _ambiguous('Category', cands.map((c) => (id: c.id, name: c.name)).toList());
      }
      return {'ok': false, 'error': 'Category not found'};
    }
    return {
      'ok': true,
      'category': {'id': cat.id, 'name': cat.name, 'description': cat.description},
    };
  }

  Future<Map<String, dynamic>> _createCategory(Map<String, dynamic> args) async {
    final id = _newUuid();
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: id,
            name: args['name'] as String,
            description: Value(args['description'] as String?),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _updateCategory(Map<String, dynamic> args) async {
    final cat = await _resolveCategory(args['idOrName'] as String);
    if (cat == null) return {'ok': false, 'error': 'Category not found'};

    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await (db.update(db.categories)..where((t) => t.id.equals(cat.id))).write(
      CategoriesCompanion(
        name: args.containsKey('name') ? Value(args['name'] as String) : const Value.absent(),
        description: args.containsKey('description') ? Value(args['description'] as String?) : const Value.absent(),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
    return {'ok': true, 'id': cat.id};
  }

  Future<Map<String, dynamic>> _archiveCategory(Map<String, dynamic> args) async {
    final cat = await _resolveCategory(args['idOrName'] as String);
    if (cat == null) return {'ok': false, 'error': 'Category not found'};

    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await (db.update(db.categories)..where((t) => t.id.equals(cat.id))).write(
      CategoriesCompanion(archived: const Value(true), updatedAt: Value(now), dirty: const Value(true)),
    );
    await _writeTombstone('categories', cat.id);
    return {'ok': true, 'id': cat.id};
  }

  // ───── Tag tools ─────

  Future<Map<String, dynamic>> _listTags(Map<String, dynamic> args) async {
    final includeArchived = args['includeArchived'] == true;
    final query = db.select(db.tags);
    if (!includeArchived) {
      query.where((t) => t.archived.equals(false));
    }
    final rows = await query.get();
    return {
      'ok': true,
      'tags': rows.map((t) => {'id': t.id, 'name': t.name, 'parentId': t.parentId, 'color': t.color}).toList(),
    };
  }

  Future<Map<String, dynamic>> _getTag(Map<String, dynamic> args) async {
    final tag = await _resolveTag(args['idOrName'] as String);
    if (tag == null) return {'ok': false, 'error': 'Tag not found'};
    return {
      'ok': true,
      'tag': {'id': tag.id, 'name': tag.name, 'parentId': tag.parentId, 'color': tag.color},
    };
  }

  Future<Map<String, dynamic>> _createTag(Map<String, dynamic> args) async {
    String? parentId;
    if (args['parentIdOrName'] != null) {
      final parent = await _resolveTag(args['parentIdOrName'] as String);
      if (parent == null) {
        return {'ok': false, 'error': 'Parent tag not found'};
      }
      parentId = parent.id;
    }
    final id = _newUuid();
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await db
        .into(db.tags)
        .insert(
          TagsCompanion.insert(
            id: id,
            name: args['name'] as String,
            description: Value(args['description'] as String?),
            parentId: Value(parentId),
            color: Value(args['color'] as String?),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _updateTag(Map<String, dynamic> args) async {
    final tag = await _resolveTag(args['idOrName'] as String);
    if (tag == null) return {'ok': false, 'error': 'Tag not found'};

    Value<String?> parentValue = const Value.absent();
    if (args.containsKey('parentIdOrName')) {
      final raw = args['parentIdOrName'];
      if (raw == null) {
        parentValue = const Value(null);
      } else {
        final parent = await _resolveTag(raw as String);
        if (parent == null) {
          return {'ok': false, 'error': 'Parent tag not found'};
        }
        parentValue = Value(parent.id);
      }
    }

    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await (db.update(db.tags)..where((t) => t.id.equals(tag.id))).write(
      TagsCompanion(
        name: args.containsKey('name') ? Value(args['name'] as String) : const Value.absent(),
        description: args.containsKey('description') ? Value(args['description'] as String?) : const Value.absent(),
        parentId: parentValue,
        color: args.containsKey('color') ? Value(args['color'] as String?) : const Value.absent(),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
    return {'ok': true, 'id': tag.id};
  }

  Future<Map<String, dynamic>> _archiveTag(Map<String, dynamic> args) async {
    final tag = await _resolveTag(args['idOrName'] as String);
    if (tag == null) return {'ok': false, 'error': 'Tag not found'};

    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await (db.update(db.tags)..where((t) => t.id.equals(tag.id))).write(
      TagsCompanion(archived: const Value(true), updatedAt: Value(now), dirty: const Value(true)),
    );
    await _writeTombstone('tags', tag.id);
    return {'ok': true, 'id': tag.id};
  }

  // ───── Transaction reads ─────

  Future<Map<String, dynamic>> _listTransactions(Map<String, dynamic> args) async {
    final limit = (args['limit'] as num?)?.toInt() ?? 50;

    String? accountId;
    if (args['accountIdOrName'] != null) {
      final acc = await _resolveAccount(args['accountIdOrName'] as String);
      if (acc == null) return {'ok': false, 'error': 'Account not found'};
      accountId = acc.id;
    }
    String? categoryId;
    if (args['categoryIdOrName'] != null) {
      final cat = await _resolveCategory(args['categoryIdOrName'] as String);
      if (cat == null) return {'ok': false, 'error': 'Category not found'};
      categoryId = cat.id;
    }
    String? tagId;
    if (args['tagIdOrName'] != null) {
      final tag = await _resolveTag(args['tagIdOrName'] as String);
      if (tag == null) return {'ok': false, 'error': 'Tag not found'};
      tagId = tag.id;
    }

    final query = db.select(db.transactions)..where((t) => t.archived.equals(false));
    if (args['type'] != null) {
      query.where((t) => t.type.equals(args['type'] as String));
    }
    if (accountId != null) {
      final acc = accountId;
      query.where((t) => t.accountId.equals(acc));
    }
    if (categoryId != null) {
      final cat = categoryId;
      query.where((t) => t.categoryId.equals(cat));
    }
    if (args['status'] != null) {
      query.where((t) => t.status.equals(args['status'] as String));
    }
    if (args['dateFrom'] != null) {
      final from = parseNaturalDate(args['dateFrom'] as String);
      query.where((t) => t.date.isBiggerOrEqualValue(from));
    }
    if (args['dateTo'] != null) {
      final to = parseNaturalDate(args['dateTo'] as String);
      query.where((t) => t.date.isSmallerOrEqualValue(to));
    }
    query
      ..orderBy([(t) => OrderingTerm.desc(t.date)])
      ..limit(limit);
    var items = await query.get();

    if (tagId != null) {
      final tg = tagId;
      final joins = await (db.select(db.transactionTags)..where((j) => j.tagId.equals(tg))).get();
      final allowed = joins.map((j) => j.transactionId).toSet();
      items = items.where((t) => allowed.contains(t.id)).toList();
    }

    return {'ok': true, 'items': items.map(_serializeTransaction).toList()};
  }

  Future<Map<String, dynamic>> _getTransaction(Map<String, dynamic> args) async {
    final id = args['id'] as String;
    final txn = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (txn == null) return {'ok': false, 'error': 'Transaction not found'};
    final joins = await (db.select(db.transactionTags)..where((j) => j.transactionId.equals(id))).get();
    final result = _serializeTransaction(txn);
    result['tagIds'] = joins.map((j) => j.tagId).toList();
    return {'ok': true, 'transaction': result};
  }

  Future<Map<String, dynamic>> _getRecentTransactions(Map<String, dynamic> args) async {
    final limit = (args['limit'] as num?)?.toInt() ?? 10;
    final query = db.select(db.transactions)
      ..where((t) => t.archived.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.date)])
      ..limit(limit);
    final items = await query.get();
    return {'ok': true, 'items': items.map(_serializeTransaction).toList()};
  }

  // ───── Transaction writes ─────

  // The agent sets `dateConfirmed` when the date is certain (explicit date,
  // "today"/"yesterday") and false when it inferred or defaulted it. When the
  // arg is absent we leave the column at its default (true).
  Value<bool> _dateConfirmedValue(Map<String, dynamic> args) {
    final raw = args['dateConfirmed'];
    if (raw is bool) return Value(raw);
    print("NO HAY RAW");
    return const Value(false);
  }

  Future<Map<String, dynamic>> _addExpense(Map<String, dynamic> args) async {
    final acc = await _resolveAccount(args['accountIdOrName'] as String);
    if (acc == null) return {'ok': false, 'error': 'Account not found'};
    final cat = await _resolveCategory(args['categoryIdOrName'] as String);
    if (cat == null) return {'ok': false, 'error': 'Category not found'};

    final id = _newUuid();
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    final date = parseOptionalDate(args['date'] as String?) ?? now;
    final amount = parseAmountToCents(args['amount'] as num);

    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: id,
            type: 'expense',
            name: args['name'] as String,
            description: Value(args['description'] as String?),
            status: (args['status'] as String?) ?? 'cleared',
            date: date,
            accountId: acc.id,
            categoryId: cat.id,
            amount: amount,
            currency: acc.currency,
            dateConfirmed: _dateConfirmedValue(args),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    await _attachTags(id, args['tagIdsOrNames']);
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _addIncome(Map<String, dynamic> args) async {
    final acc = await _resolveAccount(args['accountIdOrName'] as String);
    if (acc == null) return {'ok': false, 'error': 'Account not found'};
    final cat = await _resolveCategory(args['categoryIdOrName'] as String);
    if (cat == null) return {'ok': false, 'error': 'Category not found'};

    final id = _newUuid();
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    final date = parseOptionalDate(args['date'] as String?) ?? now;
    final amount = parseAmountToCents(args['amount'] as num);

    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: id,
            type: 'income',
            name: args['name'] as String,
            description: Value(args['description'] as String?),
            status: (args['status'] as String?) ?? 'cleared',
            date: date,
            accountId: acc.id,
            categoryId: cat.id,
            amount: amount,
            currency: acc.currency,
            dateConfirmed: _dateConfirmedValue(args),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    await _attachTags(id, args['tagIdsOrNames']);
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _addTransfer(Map<String, dynamic> args) async {
    final from = await _resolveAccount(args['fromAccountIdOrName'] as String);
    if (from == null) {
      return {'ok': false, 'error': 'Source account not found'};
    }
    final to = await _resolveAccount(args['toAccountIdOrName'] as String);
    if (to == null) {
      return {'ok': false, 'error': 'Destination account not found'};
    }
    if (from.id == to.id) {
      return {'ok': false, 'error': 'Source and destination accounts must differ'};
    }
    String? categoryId;
    if (args['categoryIdOrName'] != null) {
      final cat = await _resolveCategory(args['categoryIdOrName'] as String);
      if (cat == null) return {'ok': false, 'error': 'Category not found'};
      categoryId = cat.id;
    }

    final id = _newUuid();
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    final date = parseOptionalDate(args['date'] as String?) ?? now;
    final amount = parseAmountToCents(args['amount'] as num);
    final sameCurrency = from.currency == to.currency;
    final BigInt? toAmount = args['toAmount'] != null ? parseAmountToCents(args['toAmount'] as num) : (sameCurrency ? amount : null);
    if (toAmount == null) {
      return {'ok': false, 'error': 'Cross-currency transfers require toAmount (or exchangeRate to derive it)'};
    }

    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: id,
            type: 'transfer',
            name: args['name'] as String,
            description: Value(args['description'] as String?),
            status: 'cleared',
            date: date,
            accountId: from.id,
            categoryId: categoryId ?? '',
            amount: amount,
            currency: from.currency,
            toAccountId: Value(to.id),
            toAmount: Value(toAmount),
            toCurrency: Value(to.currency),
            exchangeRate: Value((args['exchangeRate'] as num?)?.toDouble()),
            dateConfirmed: _dateConfirmedValue(args),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    await _attachTags(id, args['tagIdsOrNames']);
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _addBalanceAdjustment(Map<String, dynamic> args) async {
    final acc = await _resolveAccount(args['accountIdOrName'] as String);
    if (acc == null) return {'ok': false, 'error': 'Account not found'};

    final id = _newUuid();
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    final date = parseOptionalDate(args['date'] as String?) ?? now;
    final balanceAfter = parseAmountToCents(args['balanceAfter'] as num);
    // Local best-effort delta. The server recomputes this on sync.
    final currentBalance = await _computeAccountBalance(acc.id);
    final amount = balanceAfter - currentBalance;

    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: id,
            type: 'balance_adjustment',
            name: (args['name'] as String?) ?? 'Ajuste de saldo',
            description: Value(args['description'] as String?),
            status: 'cleared',
            date: date,
            accountId: acc.id,
            categoryId: '',
            amount: amount,
            currency: acc.currency,
            balanceAfter: Value(balanceAfter),
            dateConfirmed: _dateConfirmedValue(args),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _updateTransaction(Map<String, dynamic> args) async {
    final id = args['id'] as String;
    final txn = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (txn == null) return {'ok': false, 'error': 'Transaction not found'};

    String? categoryId;
    if (args['categoryIdOrName'] != null) {
      final cat = await _resolveCategory(args['categoryIdOrName'] as String);
      if (cat == null) return {'ok': false, 'error': 'Category not found'};
      categoryId = cat.id;
    }
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);

    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        name: args.containsKey('name') ? Value(args['name'] as String) : const Value.absent(),
        description: args.containsKey('description') ? Value(args['description'] as String?) : const Value.absent(),
        date: args['date'] != null ? Value(parseNaturalDate(args['date'] as String)) : const Value.absent(),
        dateConfirmed: _dateConfirmedValue(args),
        amount: args['amount'] != null ? Value(parseAmountToCents(args['amount'] as num)) : const Value.absent(),
        categoryId: categoryId != null ? Value(categoryId) : const Value.absent(),
        status: args.containsKey('status') ? Value(args['status'] as String) : const Value.absent(),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _deleteTransaction(Map<String, dynamic> args) async {
    final id = args['id'] as String;
    final txn = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (txn == null) return {'ok': true, 'id': id};

    // Detach joins
    final joins = await (db.select(db.transactionTags)..where((j) => j.transactionId.equals(id))).get();
    for (final j in joins) {
      await (db.delete(db.transactionTags)..where((t) => t.id.equals(j.id))).go();
      await _writeTombstone('transactionTags', j.id);
    }

    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(archived: const Value(true), updatedAt: Value(now), dirty: const Value(true)),
    );
    await _writeTombstone('transactions', id);
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _tagTransaction(Map<String, dynamic> args) async {
    final transactionId = args['transactionId'] as String;
    final raw = (args['tagIdsOrNames'] as List).cast<String>();
    final missing = <String>[];
    var added = 0;
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    for (final item in raw) {
      final tag = await _resolveTag(item);
      if (tag == null) {
        missing.add(item);
        continue;
      }
      final existing = await (db.select(
        db.transactionTags,
      )..where((j) => j.transactionId.equals(transactionId) & j.tagId.equals(tag.id))).getSingleOrNull();
      if (existing != null) continue;
      await db
          .into(db.transactionTags)
          .insert(
            TransactionTagsCompanion.insert(
              id: _newUuid(),
              transactionId: transactionId,
              tagId: tag.id,
              createdAt: now,
              updatedAt: now,
              dirty: const Value(true),
            ),
          );
      added += 1;
    }
    return {'ok': true, 'added': added, 'missing': missing};
  }

  Future<Map<String, dynamic>> _untagTransaction(Map<String, dynamic> args) async {
    final transactionId = args['transactionId'] as String;
    final raw = (args['tagIdsOrNames'] as List).cast<String>();
    final missing = <String>[];
    var removed = 0;
    for (final item in raw) {
      final tag = await _resolveTag(item);
      if (tag == null) {
        missing.add(item);
        continue;
      }
      final join = await (db.select(
        db.transactionTags,
      )..where((j) => j.transactionId.equals(transactionId) & j.tagId.equals(tag.id))).getSingleOrNull();
      if (join == null) continue;
      await (db.delete(db.transactionTags)..where((t) => t.id.equals(join.id))).go();
      await _writeTombstone('transactionTags', join.id);
      removed += 1;
    }
    return {'ok': true, 'removed': removed, 'missing': missing};
  }

  // ───── Summaries ─────

  Future<Map<String, dynamic>> _summarizeByCategory(Map<String, dynamic> args) async {
    final from = parseNaturalDate(args['dateFrom'] as String);
    final to = parseNaturalDate(args['dateTo'] as String);
    final typeFilter = args['type'] as String?;
    final currencyFilter = args['currency'] as String?;

    final query = db.select(db.transactions)
      ..where((t) => t.archived.equals(false))
      ..where((t) => t.date.isBiggerOrEqualValue(from))
      ..where((t) => t.date.isSmallerOrEqualValue(to));
    if (typeFilter != null) {
      query.where((t) => t.type.equals(typeFilter));
    }
    final items = await query.get();

    final totals = <String, BigInt>{};
    for (final t in items) {
      if (t.type == 'transfer') continue;
      if (currencyFilter != null && t.currency != currencyFilter) continue;
      totals[t.categoryId] = (totals[t.categoryId] ?? BigInt.zero) + t.amount;
    }

    final cats = await (db.select(db.categories)..where((c) => c.archived.equals(false))).get();
    final nameById = {for (final c in cats) c.id: c.name};

    return {
      'ok': true,
      'rows': totals.entries
          .map((e) => {'categoryId': e.key, 'name': nameById[e.key] ?? '(unknown)', 'total': e.value.toDouble() / 100})
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _summarizeByAccount(Map<String, dynamic> args) async {
    final from = parseNaturalDate(args['dateFrom'] as String);
    final to = parseNaturalDate(args['dateTo'] as String);

    final items =
        await (db.select(db.transactions)
              ..where((t) => t.archived.equals(false))
              ..where((t) => t.date.isBiggerOrEqualValue(from))
              ..where((t) => t.date.isSmallerOrEqualValue(to)))
            .get();
    final accounts = await (db.select(db.accounts)..where((a) => a.archived.equals(false))).get();

    final rows = <String, ({String name, String currency, BigInt inSum, BigInt outSum})>{};
    for (final a in accounts) {
      rows[a.id] = (name: a.name, currency: a.currency, inSum: BigInt.zero, outSum: BigInt.zero);
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
        rows[t.accountId] = (name: cur.name, currency: cur.currency, inSum: nextIn, outSum: nextOut);
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

    return {
      'ok': true,
      'rows': rows.entries
          .map(
            (e) => {
              'accountId': e.key,
              'name': e.value.name,
              'currency': e.value.currency,
              'in': e.value.inSum.toDouble() / 100,
              'out': e.value.outSum.toDouble() / 100,
              'net': (e.value.inSum - e.value.outSum).toDouble() / 100,
            },
          )
          .toList(),
    };
  }

  // ───── Internal helpers ─────

  Map<String, dynamic> _serializeTransaction(Transaction t) {
    return {
      'id': t.id,
      'type': t.type,
      'name': t.name,
      'date': t.date.toString(),
      'accountId': t.accountId,
      'categoryId': t.categoryId,
      'amount': t.amount.toDouble() / 100,
      'currency': t.currency,
      'toAccountId': t.toAccountId,
      'toAmount': t.toAmount != null ? t.toAmount!.toDouble() / 100 : null,
      'status': t.status,
      'balanceAfter': t.balanceAfter != null ? t.balanceAfter!.toDouble() / 100 : null,
    };
  }

  Future<BigInt> _computeAccountBalance(String accountId) async {
    final own =
        await (db.select(db.transactions)
              ..where((t) => t.accountId.equals(accountId))
              ..where((t) => t.archived.equals(false)))
            .get();
    BigInt sum = BigInt.zero;
    for (final t in own) {
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

    final incoming =
        await (db.select(db.transactions)
              ..where((t) => t.toAccountId.equals(accountId))
              ..where((t) => t.type.equals('transfer'))
              ..where((t) => t.archived.equals(false)))
            .get();
    for (final t in incoming) {
      sum += t.toAmount ?? t.amount;
    }
    return sum;
  }

  Future<void> _attachTags(String transactionId, dynamic raw) async {
    if (raw is! List) return;
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    for (final item in raw) {
      if (item is! String) continue;
      final tag = await _resolveTag(item);
      if (tag == null) continue;
      final existing = await (db.select(
        db.transactionTags,
      )..where((j) => j.transactionId.equals(transactionId) & j.tagId.equals(tag.id))).getSingleOrNull();
      if (existing != null) continue;
      await db
          .into(db.transactionTags)
          .insert(
            TransactionTagsCompanion.insert(
              id: _newUuid(),
              transactionId: transactionId,
              tagId: tag.id,
              createdAt: now,
              updatedAt: now,
              dirty: const Value(true),
            ),
          );
    }
  }

  Future<void> _writeTombstone(String table, String entityId) async {
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    final existing = await (db.select(
      db.tombstones,
    )..where((t) => t.entityTable.equals(table) & t.entityId.equals(entityId))).getSingleOrNull();
    if (existing != null) {
      await (db.update(db.tombstones)..where((t) => t.entityTable.equals(table) & t.entityId.equals(entityId))).write(
        TombstonesCompanion(deletedAt: Value(now), updatedAt: Value(now), dirty: const Value(true)),
      );
    } else {
      await db
          .into(db.tombstones)
          .insert(
            TombstonesCompanion.insert(
              entityTable: table,
              entityId: entityId,
              deletedAt: now,
              createdAt: now,
              updatedAt: now,
              dirty: const Value(true),
            ),
          );
    }
  }

  String _newUuid() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final s = bytes.map(hex).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
        '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }
}
