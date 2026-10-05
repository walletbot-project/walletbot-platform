import 'dart:math' as math;

import '../data/data.dart';

/// Per-user prompt suggestions for the empty Gasti screen.
///
/// Port of packages/shared/src/prompt-suggestions.ts. Both run the fixture
/// table in prompt-suggestions-fixtures.json, so the seeded random source, the
/// draw order and the tie-breaks have to stay identical on both sides.
enum PromptSuggestionKind {
  logExpense,
  spentInCategoryThisMonth,
  accountBalance,
  topSpendingThisMonth,
  compareCategoryLastMonth,
  transfer,
  logIncome,
  spentWithTag,
  recentExpenses,
  whatCanYouDo,
  createCashAccount,
  setupCategories,
  howToLogExpense,
  homeWidget,
}

class PromptSuggestion {
  const PromptSuggestion(
    this.kind, {
    this.category,
    this.account,
    this.toAccount,
    this.tag,
    this.amountCents,
  });

  final PromptSuggestionKind kind;
  final String? category;
  final String? account;
  final String? toAccount;
  final String? tag;
  final int? amountCents;

  String get key => [
    kind.name,
    category ?? '',
    account ?? '',
    toAccount ?? '',
    tag ?? '',
    amountCents?.toString() ?? '',
  ].join('|');

  @override
  String toString() => key;
}

class SuggestionAccount {
  const SuggestionAccount({
    required this.id,
    required this.name,
    required this.currency,
  });

  final String id;
  final String name;
  final String currency;
}

class SuggestionCategory {
  const SuggestionCategory({required this.id, required this.name});

  final String id;
  final String name;
}

class SuggestionTag {
  const SuggestionTag({required this.name, required this.usageCount});

  final String name;
  final int usageCount;
}

class SuggestionMovement {
  const SuggestionMovement({
    required this.type,
    required this.amountCents,
    required this.currency,
    required this.accountId,
    required this.categoryId,
    this.toAccountId,
  });

  final String type;
  final int amountCents;
  final String currency;
  final String accountId;
  final String categoryId;
  final String? toAccountId;
}

class SuggestionData {
  const SuggestionData({
    required this.accounts,
    required this.categories,
    required this.tags,
    required this.movements,
  });

  final List<SuggestionAccount> accounts;
  final List<SuggestionCategory> categories;
  final List<SuggestionTag> tags;

  /// Newest first.
  final List<SuggestionMovement> movements;
}

const kPromptSuggestionCount = 5;

/// Every draw keeps one slot for a Home widget suggestion.
const _drawnCount = kPromptSuggestionCount - 1;
const kPromptSuggestionMovementsCap = 50;
const _maxUsesPerCategory = 2;
const _redrawAttempts = 6;

const _kindWeights = [
  (PromptSuggestionKind.logExpense, 3),
  (PromptSuggestionKind.spentInCategoryThisMonth, 3),
  (PromptSuggestionKind.accountBalance, 2),
  (PromptSuggestionKind.topSpendingThisMonth, 2),
  (PromptSuggestionKind.compareCategoryLastMonth, 1),
  (PromptSuggestionKind.transfer, 1),
  (PromptSuggestionKind.logIncome, 1),
  (PromptSuggestionKind.spentWithTag, 1),
  (PromptSuggestionKind.recentExpenses, 1),
];

const _actionKinds = {
  PromptSuggestionKind.logExpense,
  PromptSuggestionKind.transfer,
  PromptSuggestionKind.logIncome,
};

const _starterKinds = [
  PromptSuggestionKind.whatCanYouDo,
  PromptSuggestionKind.createCashAccount,
  PromptSuggestionKind.setupCategories,
  PromptSuggestionKind.howToLogExpense,
];

/// Seeded uniform [0, 1) source, bit for bit the TS `mulberry32`.
double Function() mulberry32(int seed) {
  var a = seed & 0xFFFFFFFF;
  int imul(int x, int y) => (x * y) & 0xFFFFFFFF;
  return () {
    a = (a + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = imul(a ^ (a >> 15), 1 | a);
    t = ((t + imul(t ^ (t >> 7), 61 | t)) & 0xFFFFFFFF) ^ t;
    return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296;
  };
}

String promptSuggestionSetKey(List<PromptSuggestion> suggestions) =>
    (suggestions.map((s) => s.key).toList()..sort()).join('\n');

String _lastShown = '';

/// The suggestions for one open of the screen. Never the exact set shown on
/// the previous open, unless the user's data only allows one set.
List<PromptSuggestion> nextPromptSuggestions(
  SuggestionData data, {
  double Function()? random,
}) {
  final suggestions = generatePromptSuggestions(
    data,
    random: random ?? mulberry32(math.Random().nextInt(1 << 32)),
    previous: _lastShown,
  );
  _lastShown = promptSuggestionSetKey(suggestions);
  return suggestions;
}

List<PromptSuggestion> generatePromptSuggestions(
  SuggestionData data, {
  required double Function() random,
  String? previous,
}) {
  final stats = _Stats.from(data);
  if (stats.expenses.isEmpty &&
      stats.incomes.isEmpty &&
      stats.transfers.isEmpty) {
    final starters = _shuffle([
      for (final kind in _starterKinds) PromptSuggestion(kind),
    ], random).take(_drawnCount);
    return _shuffle([
      ...starters,
      const PromptSuggestion(PromptSuggestionKind.homeWidget),
    ], random);
  }
  var drawn = <PromptSuggestion>[];
  for (var attempt = 0; attempt < _redrawAttempts; attempt++) {
    drawn = _draw(stats, random);
    if (promptSuggestionSetKey(drawn) != previous) break;
  }
  return drawn;
}

/// Amounts are suggestions to edit, not records: two significant digits, in
/// integer cents so both languages agree (3487 → 3500, 34.87 → 35).
int niceAmountCents(int cents) {
  final value = cents.abs();
  final digits = value.toString().length;
  if (digits <= 2) return value;
  final step = math.pow(10, digits - 2).toInt();
  return (value + step ~/ 2) ~/ step * step;
}

Future<SuggestionData> loadSuggestionData(AppRepositories repositories) async {
  final accounts = await repositories.accounts.listActive();
  final categories = await repositories.categories.listActive();
  final tags = await repositories.tags.watchWithCounts().first;
  final movements = await repositories.transactions.list(
    const TransactionFilter(),
    limit: kPromptSuggestionMovementsCap,
    ordering: TxnOrdering.dateDesc,
  );
  return SuggestionData(
    accounts: [
      for (final account in accounts)
        SuggestionAccount(
          id: account.id,
          name: account.name,
          currency: account.currency,
        ),
    ],
    categories: [
      for (final category in categories)
        SuggestionCategory(id: category.id, name: category.name),
    ],
    tags: [
      for (final entry in tags)
        SuggestionTag(name: entry.tag.name, usageCount: entry.transactionCount),
    ],
    movements: [
      for (final txn in movements)
        SuggestionMovement(
          type: txn.type,
          amountCents: txn.amount.toInt(),
          currency: txn.currency,
          accountId: txn.accountId,
          categoryId: txn.categoryId,
          toAccountId: txn.toAccountId,
        ),
    ],
  );
}

class _Expense {
  const _Expense(this.categoryId, this.accountId, this.cents);

  final String categoryId;
  final String accountId;
  final int cents;
}

void _increment(Map<String, int> map, String key) =>
    map.update(key, (n) => n + 1, ifAbsent: () => 1);

class _Stats {
  _Stats._(this.data)
    : accountsById = {for (final a in data.accounts) a.id: a},
      categoryNames = {for (final c in data.categories) c.id: c.name};

  factory _Stats.from(SuggestionData data) {
    final stats = _Stats._(data);
    for (final m in data.movements) {
      if (stats.accountsById.containsKey(m.accountId)) {
        _increment(stats.accountUses, m.accountId);
      }
      if (m.type == 'expense') {
        if (stats.categoryNames.containsKey(m.categoryId) &&
            stats.accountsById.containsKey(m.accountId)) {
          stats.expenses.add(
            _Expense(m.categoryId, m.accountId, m.amountCents.abs()),
          );
        }
      } else if (m.type == 'income') {
        if (stats.accountsById.containsKey(m.accountId)) stats.incomes.add(m);
      } else if (m.type == 'transfer') {
        final to = m.toAccountId;
        if (to != null &&
            to.isNotEmpty &&
            to != m.accountId &&
            stats.accountsById.containsKey(m.accountId) &&
            stats.accountsById.containsKey(to)) {
          stats.transfers.add(m);
          _increment(stats.accountUses, to);
        }
      }
    }
    for (final e in stats.expenses) {
      _increment(stats.categoryUses, e.categoryId);
    }
    for (final a in data.accounts) {
      stats.sameCurrencyAccounts.putIfAbsent(a.currency, () => []).add(a);
    }
    stats.sameCurrencyAccounts.removeWhere((_, group) => group.length < 2);
    stats.usedTags.addAll(data.tags.where((t) => t.usageCount > 0));
    return stats;
  }

  final SuggestionData data;
  final Map<String, SuggestionAccount> accountsById;
  final Map<String, String> categoryNames;
  final Map<String, int> accountUses = {};
  final Map<String, int> categoryUses = {};
  final List<_Expense> expenses = [];
  final List<SuggestionMovement> incomes = [];
  final List<SuggestionMovement> transfers = [];
  final List<SuggestionTag> usedTags = [];
  final Map<String, List<SuggestionAccount>> sameCurrencyAccounts = {};

  List<String> get transferCurrencies => [
    for (final currency in sameCurrencyAccounts.keys)
      if (expenses.any((e) => accountsById[e.accountId]?.currency == currency))
        currency,
  ];

  bool applies(PromptSuggestionKind kind) => switch (kind) {
    PromptSuggestionKind.logExpense ||
    PromptSuggestionKind.spentInCategoryThisMonth ||
    PromptSuggestionKind.compareCategoryLastMonth ||
    PromptSuggestionKind.recentExpenses => expenses.isNotEmpty,
    PromptSuggestionKind.accountBalance => data.accounts.isNotEmpty,
    PromptSuggestionKind.topSpendingThisMonth => expenses.length >= 5,
    PromptSuggestionKind.transfer =>
      transfers.isNotEmpty || transferCurrencies.isNotEmpty,
    PromptSuggestionKind.logIncome => incomes.isNotEmpty,
    PromptSuggestionKind.spentWithTag => usedTags.isNotEmpty,
    _ => false,
  };
}

List<PromptSuggestion> _draw(_Stats stats, double Function() random) {
  final weights = {for (final (kind, weight) in _kindWeights) kind: weight};
  final pool = [
    for (final (kind, _) in _kindWeights)
      if (stats.applies(kind)) kind,
  ];
  final categoryUses = <String, int>{};
  final drawn = <PromptSuggestion>[];

  void takeOne(bool Function(PromptSuggestionKind) where) {
    while (drawn.length < _drawnCount) {
      final candidates = pool.where(where).toList();
      if (candidates.isEmpty) return;
      final kind = _weightedPick(
        candidates,
        (k) => weights[k]!.toDouble(),
        random,
      );
      pool.remove(kind);
      final suggestion = _build(kind, stats, random, categoryUses);
      if (suggestion != null) {
        drawn.add(suggestion);
        return;
      }
    }
  }

  takeOne(_actionKinds.contains);
  takeOne((k) => !_actionKinds.contains(k));
  while (drawn.length < _drawnCount && pool.isNotEmpty) {
    takeOne((_) => true);
  }
  final widget = _build(
    PromptSuggestionKind.homeWidget,
    stats,
    random,
    categoryUses,
  );
  if (widget != null) drawn.add(widget);
  return _shuffle(drawn, random);
}

PromptSuggestion? _build(
  PromptSuggestionKind kind,
  _Stats stats,
  double Function() random,
  Map<String, int> categoryUses,
) {
  String? pickCategory() {
    final candidates = [
      for (final id in stats.categoryUses.keys)
        if ((categoryUses[id] ?? 0) < _maxUsesPerCategory) id,
    ];
    if (candidates.isEmpty) return null;
    final id = _weightedPick(
      candidates,
      (id) => (stats.categoryUses[id] ?? 0).toDouble(),
      random,
    );
    _increment(categoryUses, id);
    return id;
  }

  switch (kind) {
    case PromptSuggestionKind.logExpense:
      final categoryId = pickCategory();
      if (categoryId == null) return null;
      final expenses = stats.expenses
          .where((e) => e.categoryId == categoryId)
          .toList();
      final account = stats.data.accounts.length >= 2
          ? stats.accountsById[_mostFrequent([
              for (final e in expenses) e.accountId,
            ])]
          : null;
      return PromptSuggestion(
        kind,
        category: stats.categoryNames[categoryId],
        account: account?.name,
        amountCents: niceAmountCents(
          _median([for (final e in expenses) e.cents]),
        ),
      );
    case PromptSuggestionKind.spentInCategoryThisMonth:
    case PromptSuggestionKind.compareCategoryLastMonth:
      final categoryId = pickCategory();
      if (categoryId == null) return null;
      return PromptSuggestion(kind, category: stats.categoryNames[categoryId]);
    case PromptSuggestionKind.accountBalance:
      final account = _weightedPick(
        stats.data.accounts,
        (a) => (stats.accountUses[a.id] ?? 0) + 1.0,
        random,
      );
      return PromptSuggestion(kind, account: account.name);
    case PromptSuggestionKind.transfer:
      return _buildTransfer(stats, random);
    case PromptSuggestionKind.logIncome:
      final accountIds = [
        for (final id in {for (final m in stats.incomes) m.accountId}) id,
      ];
      final accountId = _weightedPick(
        accountIds,
        (id) => stats.incomes.where((m) => m.accountId == id).length.toDouble(),
        random,
      );
      return PromptSuggestion(
        kind,
        account: stats.accountsById[accountId]?.name,
        amountCents: niceAmountCents(
          _median([
            for (final m in stats.incomes)
              if (m.accountId == accountId) m.amountCents.abs(),
          ]),
        ),
      );
    case PromptSuggestionKind.spentWithTag:
      final tag = _weightedPick(
        stats.usedTags,
        (t) => t.usageCount.toDouble(),
        random,
      );
      return PromptSuggestion(kind, tag: tag.name);
    case PromptSuggestionKind.topSpendingThisMonth:
    case PromptSuggestionKind.recentExpenses:
      return PromptSuggestion(kind);
    case PromptSuggestionKind.homeWidget:
      final categoryId = pickCategory();
      return categoryId == null
          ? PromptSuggestion(kind)
          : PromptSuggestion(kind, category: stats.categoryNames[categoryId]);
    default:
      return null;
  }
}

PromptSuggestion? _buildTransfer(_Stats stats, double Function() random) {
  if (stats.transfers.isNotEmpty) {
    final transfer =
        stats.transfers[(random() * stats.transfers.length).floor()];
    final pair = [
      for (final m in stats.transfers)
        if (m.accountId == transfer.accountId &&
            m.toAccountId == transfer.toAccountId)
          m.amountCents.abs(),
    ];
    return PromptSuggestion(
      PromptSuggestionKind.transfer,
      account: stats.accountsById[transfer.accountId]?.name,
      toAccount: stats.accountsById[transfer.toAccountId]?.name,
      amountCents: niceAmountCents(_median(pair)),
    );
  }
  final currencies = stats.transferCurrencies;
  if (currencies.isEmpty) return null;
  final currency = currencies[(random() * currencies.length).floor()];
  final accounts = [...stats.sameCurrencyAccounts[currency]!];
  double weight(SuggestionAccount a) => (stats.accountUses[a.id] ?? 0) + 1.0;
  final from = _weightedPick(accounts, weight, random);
  accounts.remove(from);
  final to = _weightedPick(accounts, weight, random);
  return PromptSuggestion(
    PromptSuggestionKind.transfer,
    account: from.name,
    toAccount: to.name,
    amountCents: niceAmountCents(
      _median([
        for (final e in stats.expenses)
          if (stats.accountsById[e.accountId]?.currency == currency) e.cents,
      ]),
    ),
  );
}

T _weightedPick<T>(
  List<T> items,
  double Function(T) weight,
  double Function() random,
) {
  final total = items.fold<double>(0, (sum, item) => sum + weight(item));
  var target = random() * total;
  for (final item in items) {
    target -= weight(item);
    if (target < 0) return item;
  }
  return items.last;
}

List<T> _shuffle<T>(List<T> items, double Function() random) {
  final result = [...items];
  for (var i = result.length - 1; i > 0; i--) {
    final j = (random() * (i + 1)).floor();
    final swap = result[i];
    result[i] = result[j];
    result[j] = swap;
  }
  return result;
}

int _median(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[(sorted.length - 1) ~/ 2];
}

String _mostFrequent(List<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    _increment(counts, value);
  }
  var best = values.first;
  for (final entry in counts.entries) {
    if (entry.value > counts[best]!) best = entry.key;
  }
  return best;
}
