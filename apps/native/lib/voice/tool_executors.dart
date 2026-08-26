import 'dart:convert';

import 'package:app/components/dashboard/dashboard_layout.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/widgets/currency_picker.dart' show currencies;
import 'package:drift/drift.dart' show Value;

import '../data/data.dart';
import '../database.dart';
import '../settings/display_settings.dart';
import '../shared/money.dart' show centsToDouble;
import '../user_settings/default_currency_controller.dart';
import 'agent_generated.dart';
import 'tool_calc.dart';
import 'tool_fx.dart';
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
  ToolExecutors(
    this.repos, {
    this.displaySettings,
    this.defaultCurrency,
    this.fxQuotes,
  });

  final AppRepositories repos;

  /// Device-scoped display settings (app-scoped controller, passed by
  /// reference at factory construction — see main.dart). Null in contexts
  /// that have no display surface (some tests); `updateSettings` then reports
  /// the setting as unavailable instead of crashing.
  final DisplaySettingsController? displaySettings;

  /// The account's default currency controller (account-scoped, same subtree
  /// as [repos]).
  final DefaultCurrencyController? defaultCurrency;

  /// Reads the device's cached exchange-rate snapshot (backed by
  /// `FxRatesController`, passed by reference at factory construction — see
  /// main.dart). A function rather than the controller itself so the executor
  /// depends only on the quotes, never on the fetching. Null in contexts that
  /// have no cache; `getExchangeRate` then reports the rates as unavailable
  /// instead of crashing.
  final List<FxQuote> Function()? fxQuotes;

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
        // Summaries
        case 'summarizeTransactions':
          return await _summarizeTransactions(args);
        // Saved filters
        case 'listSavedFilters':
          return await _listSavedFilters(args);
        case 'createSavedFilter':
          return await _createSavedFilter(args);
        case 'updateSavedFilter':
          return await _updateSavedFilter(args);
        case 'archiveSavedFilter':
          return await _archiveSavedFilter(args);
        // Home dashboard widgets
        case 'listDashboardWidgets':
          return await _listDashboardWidgets(args);
        case 'createDashboardWidget':
          return await _createDashboardWidget(args);
        case 'updateDashboardWidget':
          return await _updateDashboardWidget(args);
        case 'reorderDashboardWidgets':
          return await _reorderDashboardWidgets(args);
        case 'archiveDashboardWidget':
          return await _archiveDashboardWidget(args);
        // Agent memory
        case 'addMemory':
          return await _addMemory(args);
        case 'updateMemory':
          return await _updateMemory(args);
        case 'forgetMemory':
          return await _forgetMemory(args);
        // Settings
        case 'updateSettings':
          return await _updateSettings(args);
        // Math & dates
        case 'calculate':
          return _calculate(args);
        case 'calculateDate':
          return _calculateDate(args);
        // Exchange rates
        case 'getExchangeRate':
          return _getExchangeRate(args);
        // Skills
        case 'readSkill':
          return _readSkill(args);
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
      currency: args['currency'] as String? ?? repos.defaultCurrency(),
      createdBy: 'agent',
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
      color: args['color'] is String
          ? Value(args['color'] as String)
          : const Value.absent(),
      icon: args['icon'] is String
          ? Value(args['icon'] as String)
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
            (c) => {
              'id': c.id,
              'name': c.name,
              'description': c.description,
              'color': c.color,
              'icon': c.icon,
              'isArchived': c.archived,
            },
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
            'color': value.color,
            'icon': value.icon,
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
      color: args['color'] as String?,
      icon: args['icon'] as String?,
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
      color: args['color'] is String
          ? Value(args['color'] as String)
          : const Value.absent(),
      icon: args['icon'] is String
          ? Value(args['icon'] as String)
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
              'isArchived': t.archived,
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
      color: args['color'] is String
          ? Value(args['color'] as String)
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
    // With no filters at all this is the "recent movements" read the old
    // getRecentTransactions tool used to serve: default to 10.
    final hasFilters =
        args['type'] != null ||
        args['accountIdOrName'] != null ||
        args['categoryIdOrName'] != null ||
        args['tagIdOrName'] != null ||
        args['status'] != null ||
        args['dateFrom'] != null ||
        args['dateTo'] != null;
    final limit = (args['limit'] as num?)?.toInt() ?? (hasFilters ? 50 : 10);

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

  // ───── Transaction writes ─────

  // A supplied date is explicit (including deterministic relative phrases).
  // When date is omitted, the executor defaults the day to today and marks it
  // unconfirmed. This prevents a mistaken model boolean from overriding the
  // actual tool payload.
  bool _dateConfirmedOf(Map<String, dynamic> args) {
    final date = args['date'];
    return date is String && date.trim().isNotEmpty;
  }

  TransactionTimeStatus _timeStatusOf(Map<String, dynamic> args) {
    return switch (args['timeStatus']) {
      'confirmed' => TransactionTimeStatus.confirmed,
      'approximation' => TransactionTimeStatus.approximation,
      'none' || null => TransactionTimeStatus.none,
      final value => throw ArgumentError('Invalid timeStatus: $value'),
    };
  }

  BigInt _transactionDateOf(Map<String, dynamic> args) {
    return parseTransactionDate(
      args['date'] as String?,
      timeStatus: _timeStatusOf(args),
      time: args['time'] as String?,
    );
  }

  // Partial temporal edits must preserve whichever of the calendar date /
  // clock the caller omitted, instead of anchoring the missing half to "now"
  // (mirrors the web executor). The omitted component is backfilled from the
  // stored timestamp. The status forced into `parseTransactionDate` only
  // drives parsing (an explicit clock is always respected); the persisted
  // `timeStatus` comes from the args, handled separately at the call site.
  BigInt _updatedTransactionDate(Map<String, dynamic> args, Transaction txn) {
    final existing = DateTime.fromMillisecondsSinceEpoch(txn.date.toInt());
    String pad(int n) => n.toString().padLeft(2, '0');
    final date =
        (args['date'] as String?) ??
        '${existing.year}-${pad(existing.month)}-${pad(existing.day)}';
    final time =
        (args['time'] as String?) ??
        '${pad(existing.hour)}:${pad(existing.minute)}';
    return parseTransactionDate(
      date,
      timeStatus: TransactionTimeStatus.confirmed,
      time: time,
    );
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
      createdBy: 'agent',
      description: args['description'] as String?,
      status: (args['status'] as String?) ?? 'cleared',
      dateMs: _transactionDateOf(args),
      dateConfirmed: _dateConfirmedOf(args),
      timeStatus: _timeStatusOf(args),
      tagIds: await _resolveTagIds(args['tagIdsOrNames']),
    );
    return _transactionWriteResult(id);
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
      createdBy: 'agent',
      description: args['description'] as String?,
      status: (args['status'] as String?) ?? 'cleared',
      dateMs: _transactionDateOf(args),
      dateConfirmed: _dateConfirmedOf(args),
      timeStatus: _timeStatusOf(args),
      tagIds: await _resolveTagIds(args['tagIdsOrNames']),
    );
    return _transactionWriteResult(id);
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
            'Cross-currency transfers require toAmount (the amount received on the destination side)',
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
      createdBy: 'agent',
      exchangeRate: (args['exchangeRate'] as num?)?.toDouble(),
      categoryId: categoryId ?? '',
      description: args['description'] as String?,
      dateMs: _transactionDateOf(args),
      dateConfirmed: _dateConfirmedOf(args),
      timeStatus: _timeStatusOf(args),
      tagIds: await _resolveTagIds(args['tagIdsOrNames']),
    );
    return _transactionWriteResult(id);
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
      createdBy: 'agent',
      name: (args['name'] as String?) ?? 'Ajuste de saldo',
      description: args['description'] as String?,
      dateMs: _transactionDateOf(args),
      dateConfirmed: _dateConfirmedOf(args),
      timeStatus: _timeStatusOf(args),
    );
    return _transactionWriteResult(id);
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
      date: args['date'] != null || args['time'] != null
          ? Value(_updatedTransactionDate(args, txn))
          : const Value.absent(),
      dateConfirmed: args['date'] != null
          ? const Value(true)
          : const Value.absent(),
      timeStatus: args.containsKey('timeStatus')
          ? Value(_timeStatusOf(args))
          : const Value.absent(),
      amount: args['amount'] != null
          ? Value(parseAmountToCents(args['amount'] as num))
          : const Value.absent(),
      categoryId: categoryId != null ? Value(categoryId) : const Value.absent(),
      status: args.containsKey('status')
          ? Value(args['status'] as String)
          : const Value.absent(),
    );

    // Tag changes ride the same tool call as the field edits. Unknown names
    // are skipped and reported back in `missing`, never created on the fly.
    final missing = <String>[];
    final toAdd = await _resolveTagIdsReporting(
      args['addTagIdsOrNames'],
      missing,
    );
    final toRemove = await _resolveTagIdsReporting(
      args['removeTagIdsOrNames'],
      missing,
    );
    if (toRemove.isNotEmpty) {
      await repos.transactions.removeTags(id, toRemove);
    }
    if (toAdd.isNotEmpty) {
      await repos.transactions.addTags(id, toAdd);
    }

    final result = await _transactionWriteResult(id);
    if (missing.isNotEmpty) result['missing'] = missing;
    return result;
  }

  /// Resolves a loosely typed tag id/name list, appending unresolved entries
  /// to [missing]. Non-list or non-string input resolves to nothing.
  Future<List<String>> _resolveTagIdsReporting(
    dynamic raw,
    List<String> missing,
  ) async {
    if (raw is! List) return const [];
    final ids = <String>[];
    for (final item in raw) {
      if (item is! String) continue;
      final tag = _valueOrNull(await repos.resolver.tag(item));
      if (tag == null) {
        missing.add(item);
      } else {
        ids.add(tag.id);
      }
    }
    return ids;
  }

  Future<Map<String, dynamic>> _deleteTransaction(
    Map<String, dynamic> args,
  ) async {
    final id = args['id'] as String;
    // Idempotent: deleting a missing transaction still reports ok.
    await repos.transactions.delete(id);
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _transactionWriteResult(String id) async {
    final transaction = await repos.transactions.getById(id);
    if (transaction == null) {
      return {'ok': true, 'id': id};
    }
    return {
      'ok': true,
      'id': id,
      'date': transaction.date.toString(),
      'timeStatus': transaction.timeStatus.name,
    };
  }

  // ───── Summaries ─────

  Future<Map<String, dynamic>> _summarizeTransactions(
    Map<String, dynamic> args,
  ) async {
    final groupBy = args['groupBy'];
    final fromMs = parseNaturalDate(args['dateFrom'] as String);
    final toMs = parseNaturalDate(args['dateTo'] as String);
    if (groupBy == 'category') {
      final rows = await repos.summaries.byCategory(
        fromMs: fromMs,
        toMs: toMs,
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
    if (groupBy == 'account') {
      final rows = await repos.summaries.byAccount(fromMs: fromMs, toMs: toMs);
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
    return {'ok': false, 'error': 'Invalid groupBy: $groupBy'};
  }

  // ───── Saved filter tools ─────

  Future<Map<String, dynamic>> _listSavedFilters(
    Map<String, dynamic> args,
  ) async {
    final filters = await repos.savedFilters.listActive();
    return {'ok': true, 'filters': filters.map(_serializeSavedFilter).toList()};
  }

  Future<Map<String, dynamic>> _createSavedFilter(
    Map<String, dynamic> args,
  ) async {
    final name = (args['name'] as String).trim();
    if (name.isEmpty) return {'ok': false, 'error': 'Filter name is required'};
    final config = _canonicalFilterConfig(args['filterConfigJson'] as String);
    final id = await repos.savedFilters.create(name: name, config: config);
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _updateSavedFilter(
    Map<String, dynamic> args,
  ) async {
    final id = args['id'] as String;
    final existing = await repos.savedFilters.getById(id);
    if (existing == null || existing.archived) {
      return {'ok': false, 'error': 'Saved filter not found'};
    }
    final name = args.containsKey('name')
        ? Value((args['name'] as String).trim())
        : const Value<String>.absent();
    final config = args.containsKey('filterConfigJson')
        ? Value(_canonicalFilterConfig(args['filterConfigJson'] as String))
        : const Value<String>.absent();
    await repos.savedFilters.update(id, name: name, config: config);
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _archiveSavedFilter(
    Map<String, dynamic> args,
  ) async {
    final id = args['id'] as String;
    await repos.savedFilters.archive(id);
    return {'ok': true, 'id': id};
  }

  // ───── Dashboard widget tools ─────

  Future<Map<String, dynamic>> _listDashboardWidgets(
    Map<String, dynamic> args,
  ) async {
    final widgets = await repos.dashboard.listActive();
    final filters = {
      for (final filter in await repos.savedFilters.listActive())
        filter.id: filter,
    };
    return {
      'ok': true,
      'widgets': widgets
          .map((widget) => _serializeDashboardWidget(widget, filters))
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _createDashboardWidget(
    Map<String, dynamic> args,
  ) async {
    final type = _widgetType(args['type']);
    if (type == null) return {'ok': false, 'error': 'Invalid widget type'};
    final title = (args['title'] as String).trim();
    if (title.isEmpty) {
      return {'ok': false, 'error': 'Widget title is required'};
    }

    final optionsResult = _widgetOptionsFor(type, title, args);
    if (optionsResult.error != null) {
      return {'ok': false, 'error': optionsResult.error};
    }

    final existing = await repos.dashboard.listActive();
    final width = _dashboardWidth(args['width']) ?? _defaultWidthFor(type);
    // Place the new widget on a fresh row below everything else, matching the
    // manual-grid layout the UI uses (coordinates live in `options.layout`).
    final layout = DashboardGridLayout.fromPlacements(
      resolvePlacements([
        for (final row in existing)
          PlacementInput(
            id: row.id,
            width: DashboardWidth.fromWire(row.width) ?? DashboardWidth.full,
            coord: dashboardLayoutFromOptions(row.options),
          ),
      ]),
    );
    final filterId = await _createFilterForWidget(type, title, args);
    final id = await repos.dashboard.create(
      type: type.wire,
      filterId: filterId,
      position: existing.length,
      width: width.wire,
      options: encodeWidgetOptions({
        ...optionsResult.options,
        'layout': {'row': layout.rowCount, 'col': 0},
      }),
    );
    return {'ok': true, 'id': id, 'filterId': filterId};
  }

  Future<Map<String, dynamic>> _updateDashboardWidget(
    Map<String, dynamic> args,
  ) async {
    final id = args['id'] as String;
    final existing = await repos.dashboard.getById(id);
    if (existing == null || existing.archived) {
      return {'ok': false, 'error': 'Dashboard widget not found'};
    }

    final currentType = _widgetType(existing.type);
    final nextType = args.containsKey('type')
        ? _widgetType(args['type'])
        : currentType;
    if (nextType == null) return {'ok': false, 'error': 'Invalid widget type'};

    final currentOptions = _decodeJsonMap(existing.options);
    final title = args.containsKey('title')
        ? (args['title'] as String).trim()
        : (currentOptions['title'] as String? ?? '').trim();
    if (title.isEmpty) {
      return {'ok': false, 'error': 'Widget title is required'};
    }

    final optionsResult = _widgetOptionsFor(
      nextType,
      title,
      args,
      existingOptions: currentOptions,
    );
    if (optionsResult.error != null) {
      return {'ok': false, 'error': optionsResult.error};
    }

    final filterId = await _filterIdForWidgetUpdate(
      existing,
      nextType,
      title,
      args,
    );
    final width = _dashboardWidth(args['width']);
    await repos.dashboard.update(
      id,
      type: args.containsKey('type')
          ? Value(nextType.wire)
          : const Value.absent(),
      filterId: Value(filterId),
      width: width != null ? Value(width.wire) : const Value.absent(),
      options: Value(
        mergeWidgetOptions(existing.options, optionsResult.options),
      ),
    );
    return {'ok': true, 'id': id, 'filterId': filterId};
  }

  Future<Map<String, dynamic>> _reorderDashboardWidgets(
    Map<String, dynamic> args,
  ) async {
    final rawIds = args['ids'];
    if (rawIds is! List) {
      return {'ok': false, 'error': 'ids must be a list'};
    }
    final ids = rawIds.whereType<String>().toList();
    if (ids.length != rawIds.length) {
      return {'ok': false, 'error': 'ids must only contain strings'};
    }
    await repos.dashboard.reorder(ids);
    return {'ok': true, 'ids': ids};
  }

  Future<Map<String, dynamic>> _archiveDashboardWidget(
    Map<String, dynamic> args,
  ) async {
    final id = args['id'] as String;
    await repos.dashboard.archive(id);
    return {'ok': true, 'id': id};
  }

  // ───── Agent memory tools ─────

  Future<Map<String, dynamic>> _addMemory(Map<String, dynamic> args) async {
    try {
      final id = await repos.agentMemories.create(
        content: args['content'] as String,
      );
      return {'ok': true, 'id': id};
    } on StateError catch (e) {
      // The "consolidate first" cap — surface the message without the
      // "Bad state:" prefix the generic catch would add.
      return {'ok': false, 'error': e.message};
    }
  }

  Future<Map<String, dynamic>> _updateMemory(Map<String, dynamic> args) async {
    final id = args['id'] as String;
    final updated = await repos.agentMemories.update(
      id,
      content: args['content'] as String,
    );
    if (!updated) return {'ok': false, 'error': 'Memory not found'};
    return {'ok': true, 'id': id};
  }

  Future<Map<String, dynamic>> _forgetMemory(Map<String, dynamic> args) async {
    final id = args['id'] as String;
    // Idempotent, like deleteTransaction: forgetting a missing memory is ok.
    await repos.agentMemories.archive(id);
    return {'ok': true, 'id': id};
  }

  // ───── Settings tool ─────

  Future<Map<String, dynamic>> _updateSettings(
    Map<String, dynamic> args,
  ) async {
    final language = args['language'] as String?;
    final theme = args['theme'] as String?;
    final currency = args['defaultCurrency'] as String?;
    if (language == null && theme == null && currency == null) {
      return {
        'ok': false,
        'error': 'Nothing to change — pass language, theme, or defaultCurrency',
      };
    }

    final changed = <String>[];
    if (language != null || theme != null) {
      final settings = displaySettings;
      if (settings == null) {
        return {
          'ok': false,
          'error': 'Display settings are not available in this session',
        };
      }
      if (language != null) {
        final value = switch (language) {
          'system' => DisplayLanguage.system,
          'es' => DisplayLanguage.spanish,
          'en' => DisplayLanguage.english,
          _ => null,
        };
        if (value == null) {
          return {'ok': false, 'error': 'Invalid language: $language'};
        }
        await settings.setLanguage(value);
        changed.add('language=$language (this device only)');
      }
      if (theme != null) {
        final value = switch (theme) {
          'system' => DisplayTheme.system,
          'light' => DisplayTheme.light,
          'dark' => DisplayTheme.dark,
          _ => null,
        };
        if (value == null) {
          return {'ok': false, 'error': 'Invalid theme: $theme'};
        }
        await settings.setTheme(value);
        changed.add('theme=$theme (this device only)');
      }
    }
    if (currency != null) {
      final controller = defaultCurrency;
      if (controller == null) {
        return {
          'ok': false,
          'error': 'Default currency is not available in this session',
        };
      }
      final normalized = currency.trim().toUpperCase();
      if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalized)) {
        return {'ok': false, 'error': 'Invalid currency code: $currency'};
      }
      // Remote accounts persist through the backend inside setValue; a
      // rejected write rolls back and propagates as the generic error
      // envelope.
      await controller.setValue(normalized);
      changed.add('defaultCurrency=$normalized (account-wide)');
    }
    return {'ok': true, 'changed': changed};
  }

  // ───── Math & date tools ─────
  // Pure local computation (lib/voice/tool_calc.dart, mirroring
  // packages/shared/src/tools/calc.ts + date-calc.ts) — no database involved.

  Map<String, dynamic> _calculate(Map<String, dynamic> args) {
    final steps = args['steps'];
    if (steps is! List) {
      return {
        'ok': false,
        'error': 'steps must be a list of {expression, name?} objects',
      };
    }
    try {
      final results = runCalculate(steps);
      return {'ok': true, 'steps': results, 'result': results.last['value']};
    } on FormatException catch (e) {
      return {'ok': false, 'error': e.message};
    }
  }

  Map<String, dynamic> _calculateDate(Map<String, dynamic> args) {
    try {
      return {'ok': true, ...runCalculateDate(args.cast<String, Object?>())};
    } on FormatException catch (e) {
      return {'ok': false, 'error': e.message};
    }
  }

  // ───── Skills tool ─────

  // ───── Exchange rates ─────

  /// Answers from the cached snapshot only (see FxRatesController): no
  /// network call happens inside a tool executor, so this works offline and
  /// returns instantly.
  Map<String, dynamic> _getExchangeRate(Map<String, dynamic> args) {
    final rawFrom = args['from'];
    final rawTo = args['to'];
    if (rawFrom is! String || rawTo is! String) {
      return {'ok': false, 'error': 'from and to are required'};
    }
    final from = normalizeCurrencyCode(rawFrom);
    final to = normalizeCurrencyCode(rawTo);
    if (!currencies.contains(from)) {
      return {'ok': false, 'error': 'Unknown currency code: $from'};
    }
    if (!currencies.contains(to)) {
      return {'ok': false, 'error': 'Unknown currency code: $to'};
    }
    if (from == to) {
      return {'ok': false, 'error': 'from and to are the same currency'};
    }

    final rawMarket = args['market'];
    final market = rawMarket is String && isFxMarket(rawMarket)
        ? rawMarket
        : kDefaultFxMarket;

    final snapshot = fxQuotes?.call() ?? const <FxQuote>[];
    if (snapshot.isEmpty) {
      return {'ok': false, 'error': 'Exchange rates are unavailable right now'};
    }
    final resolution = resolveFxQuote(snapshot, from, to, market);
    if (resolution == null) {
      return {
        'ok': false,
        'error': 'No exchange rate available for $from\u2192$to',
      };
    }

    final rawAmount = args['amount'];
    final amount = rawAmount is num ? rawAmount.toDouble() : null;
    final alternatives = fxAlternatives(snapshot, from, to);
    return {
      'ok': true,
      'from': resolution.from,
      'to': resolution.to,
      'market': resolution.market,
      'rate': resolution.rate,
      if (resolution.buy != null) 'buy': resolution.buy,
      if (resolution.sell != null) 'sell': resolution.sell,
      'source': resolution.source,
      'asOf': resolution.asOf,
      'path': resolution.path,
      if (isFxQuoteStale(
        resolution.asOf,
        DateTime.now().millisecondsSinceEpoch,
      ))
        'stale': true,
      if (amount != null) 'converted': convertAmount(amount, resolution.rate),
      if (alternatives.isNotEmpty) 'alternatives': alternatives,
    };
  }

  Map<String, dynamic> _readSkill(Map<String, dynamic> args) {
    final slug = args['slug'] as String?;
    for (final skill in kAgentSkills) {
      if (skill.slug == slug) {
        return {
          'ok': true,
          'slug': skill.slug,
          'title': skill.title,
          'body': skill.body,
        };
      }
    }
    return {
      'ok': false,
      'error': 'Unknown skill: $slug',
      'availableSlugs': [for (final skill in kAgentSkills) skill.slug],
    };
  }

  // ───── Internal helpers ─────

  Map<String, dynamic> _serializeSavedFilter(SavedFilter filter) {
    return {
      'id': filter.id,
      'name': filter.name,
      'filterConfigJson': filter.config,
      'filterConfig': _decodeJson(filter.config),
    };
  }

  Map<String, dynamic> _serializeDashboardWidget(
    DashboardWidget widget,
    Map<String, SavedFilter> filtersById,
  ) {
    final filter = widget.filterId == null
        ? null
        : filtersById[widget.filterId];
    return {
      'id': widget.id,
      'type': widget.type,
      'filterId': widget.filterId,
      'position': widget.position,
      'width': widget.width,
      'options': _decodeJson(widget.options),
      'filterConfigJson': filter?.config,
      'filterConfig': filter == null ? null : _decodeJson(filter.config),
    };
  }

  String _canonicalFilterConfig(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Filter config must be a JSON object');
    }
    final filter = TransactionFilter.fromCanonicalJson(
      Map<String, Object?>.from(decoded),
    );
    return jsonEncode(filter.toCanonicalJson());
  }

  bool _isEmptyFilterConfig(String config) {
    final decoded = jsonDecode(config);
    if (decoded is! Map) return true;
    return TransactionFilter.fromCanonicalJson(
      Map<String, Object?>.from(decoded),
    ).isEmpty;
  }

  Object? _decodeJson(String raw) {
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  Map<String, Object?> _decodeJsonMap(String raw) {
    final decoded = _decodeJson(raw);
    return decoded is Map ? Map<String, Object?>.from(decoded) : {};
  }

  WidgetType? _widgetType(Object? raw) {
    if (raw is! String) return null;
    return WidgetType.fromWire(raw);
  }

  DashboardWidth? _dashboardWidth(Object? raw) {
    if (raw is! String) return null;
    return DashboardWidth.fromWire(raw);
  }

  DashboardWidth _defaultWidthFor(WidgetType type) => switch (type) {
    WidgetType.stat => DashboardWidth.third,
    WidgetType.list => DashboardWidth.full,
    WidgetType.balance => DashboardWidth.half,
    WidgetType.chart => DashboardWidth.full,
  };

  ({Map<String, Object?> options, String? error}) _widgetOptionsFor(
    WidgetType type,
    String title,
    Map<String, dynamic> args, {
    Map<String, Object?> existingOptions = const {},
  }) {
    final options = <String, Object?>{};
    switch (type) {
      case WidgetType.stat:
        options['title'] = title;
        options['aggregation'] =
            _statAggregation(args['aggregation']) ??
            _statAggregation(existingOptions['aggregation']) ??
            StatAggregation.sum.name;
      case WidgetType.list:
        options['title'] = title;
        options['limit'] =
            _positiveInt(args['limit']) ??
            _positiveInt(existingOptions['limit']) ??
            5;
      case WidgetType.balance:
        final currency =
            args['currency'] as String? ??
            existingOptions['currency'] as String?;
        if (currency == null || currency.trim().isEmpty) {
          return (options: const {}, error: 'Balance widgets require currency');
        }
        options['title'] = title;
        options['currency'] = currency.trim().toUpperCase();
        // `accountIds` is a content key, so it is dropped before the merge: it
        // has to be re-stated on every write or a partial update that never
        // mentioned it would silently widen the card back to the whole
        // currency.
        options['accountIds'] = args.containsKey('accountIds')
            ? dashboardIdListFromJson(args['accountIds'])
            : dashboardIdListFromJson(existingOptions['accountIds']);
      case WidgetType.chart:
        options['title'] = title;
        options['groupBy'] =
            _breakdownGroupBy(args['groupBy']) ??
            _breakdownGroupBy(existingOptions['groupBy']) ??
            BreakdownGroupBy.category.wire;
        options['chartKind'] =
            _breakdownChartKind(args['chartKind']) ??
            _breakdownChartKind(existingOptions['chartKind']) ??
            BreakdownChartKind.pie.wire;
    }

    final background = args.containsKey('background')
        ? _backgroundFromArgs(args['background'])
        : existingOptions['background'];
    if (background != null) options['background'] = background;
    return (options: options, error: null);
  }

  String? _statAggregation(Object? raw) {
    if (raw is! String) return null;
    for (final value in StatAggregation.values) {
      if (value.name == raw) return value.name;
    }
    return null;
  }

  String? _breakdownGroupBy(Object? raw) {
    if (raw is! String) return null;
    return BreakdownGroupBy.fromWire(raw)?.wire;
  }

  String? _breakdownChartKind(Object? raw) {
    if (raw is! String) return null;
    return BreakdownChartKind.fromWire(raw)?.wire;
  }

  int? _positiveInt(Object? raw) {
    final value = raw is num ? raw.toInt() : null;
    return value != null && value > 0 ? value : null;
  }

  Object? _backgroundFromArgs(Object? raw) {
    if (raw is! Map) return null;
    final mode = raw['mode'];
    if (mode == 'none') return null;
    if (mode == 'fixed') {
      return {
        'mode': 'fixed',
        'fixedColor': _hex(raw['fixedColor']) ?? '#C8F2D8',
      };
    }
    if (mode == 'value') {
      final nested = raw['value'];
      final source = nested is Map ? nested : raw;
      return {
        'mode': 'value',
        'value': {
          'low': _double(source['low']) ?? 0,
          'high': _double(source['high']) ?? 10000,
          'lowColor': _hex(source['lowColor']) ?? '#FFCBCB',
          'betweenColor': _hex(source['betweenColor']) ?? '#FFE588',
          'highColor': _hex(source['highColor']) ?? '#C8F2D8',
        },
      };
    }
    return null;
  }

  String? _hex(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    return trimmed.startsWith('#') ? trimmed : '#$trimmed';
  }

  double? _double(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.replaceAll(',', '.'));
    return null;
  }

  Future<String?> _createFilterForWidget(
    WidgetType type,
    String title,
    Map<String, dynamic> args,
  ) async {
    if (type == WidgetType.balance || !args.containsKey('filterConfigJson')) {
      return null;
    }
    final config = _canonicalFilterConfig(args['filterConfigJson'] as String);
    if (_isEmptyFilterConfig(config)) return null;
    return repos.savedFilters.create(name: title, config: config);
  }

  Future<String?> _filterIdForWidgetUpdate(
    DashboardWidget existing,
    WidgetType type,
    String title,
    Map<String, dynamic> args,
  ) async {
    if (type == WidgetType.balance) return null;

    if (args.containsKey('filterConfigJson')) {
      final config = _canonicalFilterConfig(args['filterConfigJson'] as String);
      if (_isEmptyFilterConfig(config)) return null;
      if (existing.filterId != null) {
        await repos.savedFilters.update(
          existing.filterId!,
          name: Value(title),
          config: Value(config),
        );
        return existing.filterId;
      }
      return repos.savedFilters.create(name: title, config: config);
    }

    if (existing.filterId != null && args.containsKey('title')) {
      await repos.savedFilters.update(existing.filterId!, name: Value(title));
    }
    return existing.filterId;
  }

  Map<String, dynamic> _serializeTransaction(Transaction t) {
    return {
      'id': t.id,
      'type': t.type,
      'name': t.name,
      'date': t.date.toString(),
      'dateConfirmed': t.dateConfirmed,
      'timeStatus': t.timeStatus.name,
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
