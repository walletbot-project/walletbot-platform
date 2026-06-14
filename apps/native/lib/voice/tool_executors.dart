import 'package:drift/drift.dart' show Value;

import '../data/data.dart';
import '../database.dart';
import '../shared/money.dart' show centsToDouble;
import 'tool_parsing.dart';

// Native tool executors. All operations run against the local database via
// the repository layer (lib/data/); the sync layer pushes dirty rows to
// Convex. NEVER call the Convex backend directly from here — native must work
// offline.
//
// This class owns the agent *protocol*: argument coercion (Gemini's loosely
// typed function-call args) and the `{'ok': bool, ...}` JSON envelopes the
// model's prompt expects. Data semantics live in the repositories.

class ToolExecutors {
  ToolExecutors(this.repos);

  final AppRepositories repos;

  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
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

  // ───── Resolution helpers ─────

  /// Most tools treat an ambiguous name the same as not-found (the original
  /// behavior); only getAccount/getCategory surface candidates.
  T? _valueOrNull<T>(ResolveResult<T> result) =>
      result is Resolved<T> ? result.value : null;

  Map<String, dynamic> _ambiguous(
    String label,
    List<({String id, String name})> candidates,
  ) {
    return {
      'ok': false,
      'error': '$label is ambiguous',
      'candidates': candidates
          .map((c) => {'id': c.id, 'name': c.name})
          .toList(),
    };
  }

  // ───── Account tools ─────

  Future<Map<String, dynamic>> _listAccounts(Map<String, dynamic> args) async {
    final rows = await repos.accounts.listAll(
      includeArchived: args['includeArchived'] == true,
    );
    return {
      'ok': true,
      'accounts': rows
          .map(
            (a) => {
              'id': a.id,
              'name': a.name,
              'currency': a.currency,
              'color': a.color,
              'icon': a.icon,
              'isArchived': a.archived,
            },
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _getAccount(Map<String, dynamic> args) async {
    final result = await repos.resolver.account(args['idOrName'] as String);
    switch (result) {
      case Ambiguous<Account>(:final candidates):
        return _ambiguous('Account', candidates);
      case NotFound<Account>():
        return {'ok': false, 'error': 'Account not found'};
      case Resolved<Account>(:final value):
        return {
          'ok': true,
          'account': {
            'id': value.id,
            'name': value.name,
            'currency': value.currency,
            'color': value.color,
            'icon': value.icon,
          },
        };
    }
  }

  Future<Map<String, dynamic>> _getAccountBalance(
    Map<String, dynamic> args,
  ) async {
    final acc = _valueOrNull(
      await repos.resolver.account(args['idOrName'] as String),
    );
    if (acc == null) return {'ok': false, 'error': 'Account not found'};
    final balance = await repos.accounts.getBalanceCents(acc.id);
    return {
      'ok': true,
      'accountId': acc.id,
      'accountName': acc.name,
      'balance': centsToDouble(balance),
      'currency': acc.currency,
    };
  }

  Future<Map<String, dynamic>> _createAccount(Map<String, dynamic> args) async {
    final id = await repos.accounts.create(
      name: args['name'] as String,
      currency: args['currency'] as String,
      description: args['description'] as String?,
      color: args['color'] as String?,
      icon: args['icon'] as String?,
    );
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _updateAccount(Map<String, dynamic> args) async {
    final acc = _valueOrNull(
      await repos.resolver.account(args['idOrName'] as String),
    );
    if (acc == null) return {'ok': false, 'error': 'Account not found'};

    await repos.accounts.update(
      acc.id,
      name: args.containsKey('name')
          ? Value(args['name'] as String)
          : const Value.absent(),
      description: args.containsKey('description')
          ? Value(args['description'] as String?)
          : const Value.absent(),
      color: args.containsKey('color')
          ? Value(args['color'] as String?)
          : const Value.absent(),
      icon: args.containsKey('icon')
          ? Value(args['icon'] as String?)
          : const Value.absent(),
    );
    return {'ok': true, 'id': acc.id};
  }

  Future<Map<String, dynamic>> _archiveAccount(
    Map<String, dynamic> args,
  ) async {
    final acc = _valueOrNull(
      await repos.resolver.account(args['idOrName'] as String),
    );
    if (acc == null) return {'ok': false, 'error': 'Account not found'};
    await repos.accounts.archive(acc.id);
    return {'ok': true, 'id': acc.id};
  }

  // ───── Category tools ─────

  Future<Map<String, dynamic>> _listCategories(
    Map<String, dynamic> args,
  ) async {
    final rows = await repos.categories.listAll(
      includeArchived: args['includeArchived'] == true,
    );
    return {
      'ok': true,
      'categories': rows
          .map(
            (c) => {'id': c.id, 'name': c.name, 'description': c.description},
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _getCategory(Map<String, dynamic> args) async {
    final result = await repos.resolver.category(args['idOrName'] as String);
    switch (result) {
      case Ambiguous<Category>(:final candidates):
        return _ambiguous('Category', candidates);
      case NotFound<Category>():
        return {'ok': false, 'error': 'Category not found'};
      case Resolved<Category>(:final value):
        return {
          'ok': true,
          'category': {
            'id': value.id,
            'name': value.name,
            'description': value.description,
          },
        };
    }
  }

  Future<Map<String, dynamic>> _createCategory(
    Map<String, dynamic> args,
  ) async {
    final id = await repos.categories.create(
      name: args['name'] as String,
      description: args['description'] as String?,
    );
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _updateCategory(
    Map<String, dynamic> args,
  ) async {
    final cat = _valueOrNull(
      await repos.resolver.category(args['idOrName'] as String),
    );
    if (cat == null) return {'ok': false, 'error': 'Category not found'};

    await repos.categories.update(
      cat.id,
      name: args.containsKey('name')
          ? Value(args['name'] as String)
          : const Value.absent(),
      description: args.containsKey('description')
          ? Value(args['description'] as String?)
          : const Value.absent(),
    );
    return {'ok': true, 'id': cat.id};
  }

  Future<Map<String, dynamic>> _archiveCategory(
    Map<String, dynamic> args,
  ) async {
    final cat = _valueOrNull(
      await repos.resolver.category(args['idOrName'] as String),
    );
    if (cat == null) return {'ok': false, 'error': 'Category not found'};
    await repos.categories.archive(cat.id);
    return {'ok': true, 'id': cat.id};
  }

  // ───── Tag tools ─────

  Future<Map<String, dynamic>> _listTags(Map<String, dynamic> args) async {
    final rows = await repos.tags.listAll(
      includeArchived: args['includeArchived'] == true,
    );
    return {
      'ok': true,
      'tags': rows
          .map(
            (t) => {
              'id': t.id,
              'name': t.name,
              'parentId': t.parentId,
              'color': t.color,
            },
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _getTag(Map<String, dynamic> args) async {
    final tag = _valueOrNull(
      await repos.resolver.tag(args['idOrName'] as String),
    );
    if (tag == null) return {'ok': false, 'error': 'Tag not found'};
    return {
      'ok': true,
      'tag': {
        'id': tag.id,
        'name': tag.name,
        'parentId': tag.parentId,
        'color': tag.color,
      },
    };
  }

  Future<Map<String, dynamic>> _createTag(Map<String, dynamic> args) async {
    String? parentId;
    if (args['parentIdOrName'] != null) {
      final parent = _valueOrNull(
        await repos.resolver.tag(args['parentIdOrName'] as String),
      );
      if (parent == null) {
        return {'ok': false, 'error': 'Parent tag not found'};
      }
      parentId = parent.id;
    }
    final id = await repos.tags.create(
      name: args['name'] as String,
      description: args['description'] as String?,
      parentId: parentId,
      color: args['color'] as String?,
    );
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _updateTag(Map<String, dynamic> args) async {
    final tag = _valueOrNull(
      await repos.resolver.tag(args['idOrName'] as String),
    );
    if (tag == null) return {'ok': false, 'error': 'Tag not found'};

    Value<String?> parentValue = const Value.absent();
    if (args.containsKey('parentIdOrName')) {
      final raw = args['parentIdOrName'];
      if (raw == null) {
        parentValue = const Value(null);
      } else {
        final parent = _valueOrNull(await repos.resolver.tag(raw as String));
        if (parent == null) {
          return {'ok': false, 'error': 'Parent tag not found'};
        }
        parentValue = Value(parent.id);
      }
    }

    await repos.tags.update(
      tag.id,
      name: args.containsKey('name')
          ? Value(args['name'] as String)
          : const Value.absent(),
      description: args.containsKey('description')
          ? Value(args['description'] as String?)
          : const Value.absent(),
      parentId: parentValue,
      color: args.containsKey('color')
          ? Value(args['color'] as String?)
          : const Value.absent(),
    );
    return {'ok': true, 'id': tag.id};
  }

  Future<Map<String, dynamic>> _archiveTag(Map<String, dynamic> args) async {
    final tag = _valueOrNull(
      await repos.resolver.tag(args['idOrName'] as String),
    );
    if (tag == null) return {'ok': false, 'error': 'Tag not found'};
    await repos.tags.archive(tag.id, mode: TagArchiveMode.reparentChildren);
    return {'ok': true, 'id': tag.id};
  }

  // ───── Transaction reads ─────

  Future<Map<String, dynamic>> _listTransactions(
    Map<String, dynamic> args,
  ) async {
    final limit = (args['limit'] as num?)?.toInt() ?? 50;

    String? accountId;
    if (args['accountIdOrName'] != null) {
      final acc = _valueOrNull(
        await repos.resolver.account(args['accountIdOrName'] as String),
      );
      if (acc == null) return {'ok': false, 'error': 'Account not found'};
      accountId = acc.id;
    }
    String? categoryId;
    if (args['categoryIdOrName'] != null) {
      final cat = _valueOrNull(
        await repos.resolver.category(args['categoryIdOrName'] as String),
      );
      if (cat == null) return {'ok': false, 'error': 'Category not found'};
      categoryId = cat.id;
    }
    String? tagId;
    if (args['tagIdOrName'] != null) {
      final tag = _valueOrNull(
        await repos.resolver.tag(args['tagIdOrName'] as String),
      );
      if (tag == null) return {'ok': false, 'error': 'Tag not found'};
      tagId = tag.id;
    }

    // Unknown wire strings filter out everything (original SQL-equality
    // behavior) rather than throwing.
    Set<TxnType> types = const {};
    if (args['type'] != null) {
      final matches = TxnType.values.where((t) => t.wire == args['type']);
      if (matches.isEmpty) return {'ok': true, 'items': const []};
      types = {matches.single};
    }
    TxnStatus? status;
    if (args['status'] != null) {
      final matches = TxnStatus.values.where((s) => s.wire == args['status']);
      if (matches.isEmpty) return {'ok': true, 'items': const []};
      status = matches.single;
    }

    final items = await repos.transactions.list(
      TransactionFilter(
        types: types,
        status: status,
        accountIds: accountId != null ? {accountId} : const {},
        accountDirection: AccountDirection.source,
        categoryIds: categoryId != null ? {categoryId} : const {},
        tagIds: tagId != null ? {tagId} : const {},
      ),
      limit: limit,
      ordering: TxnOrdering.dateDesc,
      exactFromMs: args['dateFrom'] != null
          ? parseNaturalDate(args['dateFrom'] as String)
          : null,
      exactToInclusiveMs: args['dateTo'] != null
          ? parseNaturalDate(args['dateTo'] as String)
          : null,
    );

    return {'ok': true, 'items': items.map(_serializeTransaction).toList()};
  }

  Future<Map<String, dynamic>> _getTransaction(
    Map<String, dynamic> args,
  ) async {
    final id = args['id'] as String;
    final txn = await repos.transactions.getById(id);
    if (txn == null) return {'ok': false, 'error': 'Transaction not found'};
    final result = _serializeTransaction(txn);
    result['tagIds'] = await repos.transactions.tagIdsOf(id);
    return {'ok': true, 'transaction': result};
  }

  Future<Map<String, dynamic>> _getRecentTransactions(
    Map<String, dynamic> args,
  ) async {
    final limit = (args['limit'] as num?)?.toInt() ?? 10;
    final items = await repos.transactions.list(
      const TransactionFilter(),
      limit: limit,
      ordering: TxnOrdering.dateDesc,
    );
    return {'ok': true, 'items': items.map(_serializeTransaction).toList()};
  }

  // ───── Transaction writes ─────

  // The agent sets `dateConfirmed` when the date is certain (explicit date,
  // "today"/"yesterday") and false when it inferred or defaulted it.
  //
  // Gemini's function-call args don't guarantee a typed JSON boolean: depending
  // on the model it arrives as a real bool, the string "true"/"false", or a
  // number (1/0). We coerce all of those here. A truly unparseable value falls
  // back to false (conservative: treat the date as unconfirmed).
  bool _dateConfirmedOf(Map<String, dynamic> args) {
    final raw = args['dateConfirmed'];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return false;
  }

  /// Resolves the loosely typed `tagIdsOrNames` argument to tag ids,
  /// silently skipping anything unresolvable (original attach behavior).
  Future<List<String>> _resolveTagIds(dynamic raw) async {
    if (raw is! List) return const [];
    final ids = <String>[];
    for (final item in raw) {
      if (item is! String) continue;
      final tag = _valueOrNull(await repos.resolver.tag(item));
      if (tag == null) continue;
      ids.add(tag.id);
    }
    return ids;
  }

  Future<Map<String, dynamic>> _addExpense(Map<String, dynamic> args) async {
    final acc = _valueOrNull(
      await repos.resolver.account(args['accountIdOrName'] as String),
    );
    if (acc == null) return {'ok': false, 'error': 'Account not found'};
    final cat = _valueOrNull(
      await repos.resolver.category(args['categoryIdOrName'] as String),
    );
    if (cat == null) return {'ok': false, 'error': 'Category not found'};

    final id = await repos.transactions.addExpense(
      accountId: acc.id,
      categoryId: cat.id,
      name: args['name'] as String,
      amountCents: parseAmountToCents(args['amount'] as num),
      currency: acc.currency,
      description: args['description'] as String?,
      status: (args['status'] as String?) ?? 'cleared',
      dateMs: parseOptionalDate(args['date'] as String?),
      dateConfirmed: _dateConfirmedOf(args),
      tagIds: await _resolveTagIds(args['tagIdsOrNames']),
    );
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _addIncome(Map<String, dynamic> args) async {
    final acc = _valueOrNull(
      await repos.resolver.account(args['accountIdOrName'] as String),
    );
    if (acc == null) return {'ok': false, 'error': 'Account not found'};
    final cat = _valueOrNull(
      await repos.resolver.category(args['categoryIdOrName'] as String),
    );
    if (cat == null) return {'ok': false, 'error': 'Category not found'};

    final id = await repos.transactions.addIncome(
      accountId: acc.id,
      categoryId: cat.id,
      name: args['name'] as String,
      amountCents: parseAmountToCents(args['amount'] as num),
      currency: acc.currency,
      description: args['description'] as String?,
      status: (args['status'] as String?) ?? 'cleared',
      dateMs: parseOptionalDate(args['date'] as String?),
      dateConfirmed: _dateConfirmedOf(args),
      tagIds: await _resolveTagIds(args['tagIdsOrNames']),
    );
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _addTransfer(Map<String, dynamic> args) async {
    final from = _valueOrNull(
      await repos.resolver.account(args['fromAccountIdOrName'] as String),
    );
    if (from == null) {
      return {'ok': false, 'error': 'Source account not found'};
    }
    final to = _valueOrNull(
      await repos.resolver.account(args['toAccountIdOrName'] as String),
    );
    if (to == null) {
      return {'ok': false, 'error': 'Destination account not found'};
    }
    if (from.id == to.id) {
      return {
        'ok': false,
        'error': 'Source and destination accounts must differ',
      };
    }
    String? categoryId;
    if (args['categoryIdOrName'] != null) {
      final cat = _valueOrNull(
        await repos.resolver.category(args['categoryIdOrName'] as String),
      );
      if (cat == null) return {'ok': false, 'error': 'Category not found'};
      categoryId = cat.id;
    }

    final amount = parseAmountToCents(args['amount'] as num);
    final sameCurrency = from.currency == to.currency;
    final BigInt? toAmount = args['toAmount'] != null
        ? parseAmountToCents(args['toAmount'] as num)
        : (sameCurrency ? amount : null);
    if (toAmount == null) {
      return {
        'ok': false,
        'error':
            'Cross-currency transfers require toAmount (or exchangeRate to derive it)',
      };
    }

    final id = await repos.transactions.addTransfer(
      fromAccountId: from.id,
      toAccountId: to.id,
      name: args['name'] as String,
      amountCents: amount,
      currency: from.currency,
      toAmountCents: toAmount,
      toCurrency: to.currency,
      exchangeRate: (args['exchangeRate'] as num?)?.toDouble(),
      categoryId: categoryId ?? '',
      description: args['description'] as String?,
      dateMs: parseOptionalDate(args['date'] as String?),
      dateConfirmed: _dateConfirmedOf(args),
      tagIds: await _resolveTagIds(args['tagIdsOrNames']),
    );
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _addBalanceAdjustment(
    Map<String, dynamic> args,
  ) async {
    final acc = _valueOrNull(
      await repos.resolver.account(args['accountIdOrName'] as String),
    );
    if (acc == null) return {'ok': false, 'error': 'Account not found'};

    final id = await repos.transactions.addBalanceAdjustment(
      accountId: acc.id,
      balanceAfterCents: parseAmountToCents(args['balanceAfter'] as num),
      currency: acc.currency,
      name: (args['name'] as String?) ?? 'Ajuste de saldo',
      description: args['description'] as String?,
      dateMs: parseOptionalDate(args['date'] as String?),
      dateConfirmed: _dateConfirmedOf(args),
    );
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _updateTransaction(
    Map<String, dynamic> args,
  ) async {
    final id = args['id'] as String;
    final txn = await repos.transactions.getById(id);
    if (txn == null) return {'ok': false, 'error': 'Transaction not found'};

    String? categoryId;
    if (args['categoryIdOrName'] != null) {
      final cat = _valueOrNull(
        await repos.resolver.category(args['categoryIdOrName'] as String),
      );
      if (cat == null) return {'ok': false, 'error': 'Category not found'};
      categoryId = cat.id;
    }

    await repos.transactions.update(
      id,
      name: args.containsKey('name')
          ? Value(args['name'] as String)
          : const Value.absent(),
      description: args.containsKey('description')
          ? Value(args['description'] as String?)
          : const Value.absent(),
      date: args['date'] != null
          ? Value(parseNaturalDate(args['date'] as String))
          : const Value.absent(),
      dateConfirmed: args.containsKey('dateConfirmed')
          ? Value(_dateConfirmedOf(args))
          : const Value.absent(),
      amount: args['amount'] != null
          ? Value(parseAmountToCents(args['amount'] as num))
          : const Value.absent(),
      categoryId: categoryId != null ? Value(categoryId) : const Value.absent(),
      status: args.containsKey('status')
          ? Value(args['status'] as String)
          : const Value.absent(),
    );
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _deleteTransaction(
    Map<String, dynamic> args,
  ) async {
    final id = args['id'] as String;
    // Idempotent: deleting a missing transaction still reports ok.
    await repos.transactions.delete(id);
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _tagTransaction(
    Map<String, dynamic> args,
  ) async {
    final transactionId = args['transactionId'] as String;
    final raw = (args['tagIdsOrNames'] as List).cast<String>();
    final missing = <String>[];
    final resolved = <String>[];
    for (final item in raw) {
      final tag = _valueOrNull(await repos.resolver.tag(item));
      if (tag == null) {
        missing.add(item);
      } else {
        resolved.add(tag.id);
      }
    }
    final added = await repos.transactions.addTags(transactionId, resolved);
    return {'ok': true, 'added': added, 'missing': missing};
  }

  Future<Map<String, dynamic>> _untagTransaction(
    Map<String, dynamic> args,
  ) async {
    final transactionId = args['transactionId'] as String;
    final raw = (args['tagIdsOrNames'] as List).cast<String>();
    final missing = <String>[];
    final resolved = <String>[];
    for (final item in raw) {
      final tag = _valueOrNull(await repos.resolver.tag(item));
      if (tag == null) {
        missing.add(item);
      } else {
        resolved.add(tag.id);
      }
    }
    final removed = await repos.transactions.removeTags(
      transactionId,
      resolved,
    );
    return {'ok': true, 'removed': removed, 'missing': missing};
  }

  // ───── Summaries ─────

  Future<Map<String, dynamic>> _summarizeByCategory(
    Map<String, dynamic> args,
  ) async {
    final rows = await repos.summaries.byCategory(
      fromMs: parseNaturalDate(args['dateFrom'] as String),
      toMs: parseNaturalDate(args['dateTo'] as String),
      type: args['type'] as String?,
      currency: args['currency'] as String?,
    );
    return {
      'ok': true,
      'rows': rows
          .map(
            (r) => {
              'categoryId': r.categoryId,
              'name': r.name,
              'total': centsToDouble(r.totalCents),
            },
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _summarizeByAccount(
    Map<String, dynamic> args,
  ) async {
    final rows = await repos.summaries.byAccount(
      fromMs: parseNaturalDate(args['dateFrom'] as String),
      toMs: parseNaturalDate(args['dateTo'] as String),
    );
    return {
      'ok': true,
      'rows': rows
          .map(
            (r) => {
              'accountId': r.accountId,
              'name': r.name,
              'currency': r.currency,
              'in': centsToDouble(r.inCents),
              'out': centsToDouble(r.outCents),
              'net': centsToDouble(r.netCents),
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
      'amount': centsToDouble(t.amount),
      'currency': t.currency,
      'toAccountId': t.toAccountId,
      'toAmount': t.toAmount != null ? centsToDouble(t.toAmount!) : null,
      'status': t.status,
      'balanceAfter': t.balanceAfter != null
          ? centsToDouble(t.balanceAfter!)
          : null,
    };
  }
}
