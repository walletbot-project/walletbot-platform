import 'package:app/components/account_icons.dart';
import 'package:app/components/category_icons.dart';
import 'package:app/components/color_utils.dart';
import 'package:app/components/transaction_filters_bar.dart';
import 'package:app/components/transaction_row.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/app_navigation.dart';
import 'package:app/shared/breakpoints.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app/screens/transaction_form.dart';
import 'package:app/screens/transaction_details_sheet.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({
    super.key,
    this.initialFilter = const TransactionFilter(),
    this.filterRevision = 0,
  });

  final TransactionFilter initialFilter;
  final int filterRevision;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const _pageSize = 50;
  final _scrollController = ScrollController();

  AppNavigation? _nav;

  TransactionFilter _filter = const TransactionFilter();
  int _limit = _pageSize;

  /// Tracks the size of the most recent rendered slice so the scroll listener
  /// can tell whether the current page is full (more might exist) or short
  /// (we've reached the end).
  int _lastRenderedCount = 0;

  /// Selection for the side-by-side detail pane (expanded windows only). On
  /// compact/medium windows details are pushed as a route instead, so these
  /// stay null there.
  String? _detailTransactionId;
  TransactionDetailTransferSide? _detailTransferSide;

  Future<void> _openTransactionForm() async {
    // Pushed routes sit above the account-scoped providers; re-provide them
    // so the new route keeps using the active account's data layer.
    final repos = context.read<AppRepositories>();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => Provider<AppRepositories>.value(
          value: repos,
          child: const TransactionFormScreen(),
        ),
      ),
    );
    if (!mounted || saved != true) return;
    context.read<AppNavigation>().index = AppNavigation.activityTab;
  }

  Future<void> _openTransactionDetails(
    String transactionId, {
    TransactionDetailTransferSide? transferSide,
  }) async {
    // Expanded windows show details in the side pane; the same breakpoint
    // gates the pane in build, so selection and layout stay in agreement.
    if (windowSizeClassOf(context) == WindowSizeClass.expanded) {
      setState(() {
        _detailTransactionId = transactionId;
        _detailTransferSide = transferSide;
      });
      return;
    }
    final repos = context.read<AppRepositories>();
    // The details screen can pop back a filter (tapping its date/category/tag),
    // asking Activity to show everything matching that dimension.
    final result = await Navigator.of(context).push<TransactionFilter>(
      MaterialPageRoute(
        builder: (_) => TransactionDetailsScreen(
          transactionId: transactionId,
          repos: repos,
          transferSide: transferSide,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _filter = result;
      _resetPagination();
    });
  }

  /// Result handler for the embedded detail pane: closes it and, when the
  /// pane hands back a filter (tapped date/category/tag), applies it.
  void _onDetailResult(TransactionFilter? filter) {
    setState(() {
      _detailTransactionId = null;
      _detailTransferSide = null;
      if (filter != null) {
        _filter = filter;
        _resetPagination();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(ActivityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filterRevision == oldWidget.filterRevision) return;
    _filter = widget.initialFilter;
    _resetPagination();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe once to cross-tab navigation so another tab (the accounts
    // "Ver todas" action) can hand us a filter to apply when it switches here.
    final nav = context.read<AppNavigation>();
    if (nav != _nav) {
      _nav?.removeListener(_applyPendingFilter);
      _nav = nav..addListener(_applyPendingFilter);
      _applyPendingFilter();
    }
  }

  @override
  void dispose() {
    _nav?.removeListener(_applyPendingFilter);
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Applies any filter staged by [AppNavigation] (e.g. from an account's
  /// "Ver todas"), replacing the current filter and resetting pagination.
  void _applyPendingFilter() {
    final pending = _nav?.takePendingActivityFilter();
    if (pending == null || !mounted) return;
    setState(() {
      _filter = pending;
      _resetPagination();
    });
  }

  void _onScroll() {
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;
    if (position.pixels < position.maxScrollExtent - 300) return;
    // Only request more if we filled the current page — otherwise there's
    // nothing left to fetch, and skipping avoids re-subscribing the stream.
    if (_lastRenderedCount < _limit) return;
    setState(() => _limit += _pageSize);
  }

  void _resetPagination() {
    _limit = _pageSize;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _updateTypeChip(TxnType? value) {
    setState(() {
      _filter = _filter.copyWith(types: value == null ? const {} : {value});
      _resetPagination();
    });
  }

  void _onFiltersChanged(TransactionFilter next) {
    setState(() {
      _filter = next;
      _resetPagination();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repos = context.read<AppRepositories>();
    final showDetailPane =
        windowSizeClassOf(context) == WindowSizeClass.expanded;

    // The PageStorageKey keeps the scroll offset when the list moves between
    // full-width and pane layouts on window resize (the storage identity is
    // the key chain, not the tree position).
    final list = CustomScrollView(
      key: const PageStorageKey('activityTransactionList'),
      controller: _scrollController,
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverToBoxAdapter(
          child: TransactionFiltersBar(
            filter: _filter,
            onChanged: _onFiltersChanged,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: _FilterChips(
            selected: _filter.types.length == 1 ? _filter.types.single : null,
            onChanged: _updateTypeChip,
          ),
        ),
        _buildTransactionsSliver(repos),
      ],
    );

    final appBar = AppBar(
      title: Text(context.l10n.activity),
      actions: [
        IconButton(
          tooltip: context.l10n.addTransaction,
          onPressed: _openTransactionForm,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );

    if (!showDetailPane) {
      return Scaffold(
        appBar: appBar,
        body: SafeArea(child: list),
      );
    }

    // Split layout: the Activity app bar belongs to the list column only, and
    // the detail column brings its own (TransactionDetailsScreen's Scaffold),
    // so the divider runs the full height of the body.
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: 400,
              child: Scaffold(appBar: appBar, body: list),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: _buildDetailPane(repos)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPane(AppRepositories repos) {
    final transactionId = _detailTransactionId;
    if (transactionId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.l10n.selectTransactionDetail,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return TransactionDetailsScreen(
      // Remount per selection so the pane reloads when another row is tapped.
      key: ValueKey('$transactionId/${_detailTransferSide?.name}'),
      transactionId: transactionId,
      repos: repos,
      transferSide: _detailTransferSide,
      onResult: _onDetailResult,
    );
  }

  Widget _buildTransactionsSliver(AppRepositories repos) {
    return StreamBuilder<List<Account>>(
      stream: repos.accounts.watchAll(includeArchived: true),
      builder: (context, accountsSnapshot) {
        final accountsById = {
          for (final account in accountsSnapshot.data ?? const <Account>[])
            account.id: account,
        };

        return StreamBuilder<List<Category>>(
          stream: repos.categories.watchAll(includeArchived: true),
          builder: (context, categoriesSnapshot) {
            final categoriesById = {
              for (final category
                  in categoriesSnapshot.data ?? const <Category>[])
                category.id: category,
            };

            return StreamBuilder<List<Transaction>>(
              stream: repos.transactions.watch(
                _filter,
                limit: _limit,
                ordering: TxnOrdering.dateDesc,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          context.l10n.transactionsLoadFailed(snapshot.error!),
                        ),
                      ),
                    ),
                  );
                }

                final items = snapshot.data ?? const <Transaction>[];
                _lastRenderedCount = items.length;

                if (items.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(context.l10n.noTransactions),
                      ),
                    ),
                  );
                }

                final hasMore = items.length >= _limit;
                final entries = _buildListEntries(
                  items,
                  hasMore: hasMore,
                  accountsById: accountsById,
                  categoriesById: categoriesById,
                );

                return SliverList.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      _buildEntry(context, entries[index]),
                );
              },
            );
          },
        );
      },
    );
  }

  List<_ListEntry> _buildListEntries(
    List<Transaction> items, {
    required bool hasMore,
    required Map<String, Account> accountsById,
    required Map<String, Category> categoriesById,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entries = <_ListEntry>[];
    final sortedItems = [...items]
      ..sort((left, right) {
        final byTime = right.date.compareTo(left.date);
        if (byTime != 0) return byTime;
        final byCreation = right.createdAt.compareTo(left.createdAt);
        if (byCreation != 0) return byCreation;
        return right.id.compareTo(left.id);
      });

    DateTime? currentDay;
    for (final t in sortedItems) {
      // Group by transaction date (matches web). The list is ordered by date
      // desc above, so day headers stay contiguous.
      final dt = DateTime.fromMillisecondsSinceEpoch(t.date.toInt());
      final day = DateTime(dt.year, dt.month, dt.day);
      if (currentDay == null || day != currentDay) {
        entries.add(_HeaderEntry(label: _sectionLabel(day, today)));
        currentDay = day;
      }
      if (t.type == 'transfer') {
        entries.addAll(
          _transferEntries(
            t,
            accountsById: accountsById,
            categoriesById: categoriesById,
          ),
        );
      } else {
        entries.add(
          _TxnEntry.fromTransaction(
            t,
            amountCents: _signedAmountCents(t),
            description: _descriptionFor(t),
            visualIdentities: _visualIdentitiesFor(
              t,
              accountsById: accountsById,
              categoriesById: categoriesById,
            ),
          ),
        );
      }
    }

    if (hasMore) {
      entries.add(const _LoadingEntry());
    } else {
      entries.add(const _BottomSpaceEntry());
    }
    return entries;
  }

  Widget _buildEntry(BuildContext context, _ListEntry entry) {
    switch (entry) {
      case _HeaderEntry(:final label):
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        );
      case _TxnEntry(
        :final transactionId,
        :final title,
        :final type,
        :final amountCents,
        :final currency,
        :final dateConfirmed,
        :final description,
        :final visualIdentities,
        :final transferSide,
      ):
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TransactionRow(
            title: context.l10n.transactionName(title, type),
            amountCents: amountCents,
            currency: currency,
            dateCheck: dateConfirmed,
            description: description,
            visualIdentities: visualIdentities,
            onTap: () => _openTransactionDetails(
              transactionId,
              transferSide: transferSide,
            ),
          ),
        );
      case _LoadingEntry():
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      case _BottomSpaceEntry():
        return const SizedBox(height: 80);
    }
  }

  String _sectionLabel(DateTime day, DateTime today) {
    final diff = today.difference(day).inDays;
    if (diff == 0) return context.l10n.today;
    if (diff == 1) return context.l10n.yesterday;
    if (diff > 1 && diff < 7) {
      return formatWeekday(day, context.localeName);
    }
    return formatNumericDate(day, context.localeName);
  }

  /// Signed cents to pass to [TransactionRow]: positive renders green, negative
  /// renders in the default text color.
  int _signedAmountCents(Transaction t) {
    final amount = t.amount.toInt();
    switch (t.type) {
      case 'expense':
        return -amount.abs();
      case 'income':
      case 'transfer':
        return amount.abs();
      case 'balance_adjustment':
        return amount;
      default:
        return amount;
    }
  }

  List<_TxnEntry> _transferEntries(
    Transaction t, {
    required Map<String, Account> accountsById,
    required Map<String, Category> categoriesById,
  }) {
    final description = _descriptionFor(t);
    final sourceAmount = -t.amount.toInt().abs();
    final destinationAmount = (t.toAmount ?? t.amount).toInt().abs();
    return [
      _TxnEntry(
        transactionId: t.id,
        title: context.l10n.transferSent,
        type: t.type,
        amountCents: sourceAmount,
        currency: t.currency,
        dateConfirmed: t.dateConfirmed,
        description: description,
        transferSide: TransactionDetailTransferSide.source,
        visualIdentities: _visualIdentitiesFor(
          t,
          accountId: t.accountId,
          accountsById: accountsById,
          categoriesById: categoriesById,
        ),
      ),
      _TxnEntry(
        transactionId: t.id,
        title: context.l10n.transferReceived,
        type: t.type,
        amountCents: destinationAmount,
        currency: t.toCurrency ?? t.currency,
        dateConfirmed: t.dateConfirmed,
        description: description,
        transferSide: TransactionDetailTransferSide.destination,
        visualIdentities: _visualIdentitiesFor(
          t,
          accountId: t.toAccountId ?? t.accountId,
          accountsById: accountsById,
          categoriesById: categoriesById,
        ),
      ),
    ];
  }

  List<TransactionRowVisualIdentity> _visualIdentitiesFor(
    Transaction transaction, {
    required Map<String, Account> accountsById,
    required Map<String, Category> categoriesById,
    String? accountId,
  }) {
    final identities = <TransactionRowVisualIdentity>[];
    final account = accountsById[accountId ?? transaction.accountId];
    if (account != null) {
      identities.add(
        TransactionRowVisualIdentity(
          type: TransactionRowVisualIdentityType.account,
          label: 'Cuenta: ${account.name}',
          icon: accountIconFromName(account.icon),
          color: colorFromHex(account.color, fallback: accountDefaultColor),
        ),
      );
    }

    final categoryId = transaction.categoryId;
    if (categoryId.isNotEmpty) {
      final category = categoriesById[categoryId];
      if (category != null) {
        identities.add(
          TransactionRowVisualIdentity(
            type: TransactionRowVisualIdentityType.category,
            label: 'Categoria: ${category.name}',
            icon: categoryIconFromName(category.icon),
            color: colorFromHex(category.color, fallback: categoryDefaultColor),
          ),
        );
      }
    }

    identities.add(_timeVisualIdentityFor(transaction));

    return identities;
  }

  TransactionRowVisualIdentity _timeVisualIdentityFor(Transaction transaction) {
    final date = DateTime.fromMillisecondsSinceEpoch(transaction.date.toInt());
    final needsAttention =
        transaction.timeStatus != TransactionTimeStatus.confirmed;
    return TransactionRowVisualIdentity(
      type: TransactionRowVisualIdentityType.time,
      label: MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(date)),
      icon: needsAttention
          ? Icons.help_outline_rounded
          : Icons.schedule_outlined,
      color: Colors.transparent,
      attention: needsAttention,
    );
  }

  String? _joinDescriptions(String? first, String? second) {
    final parts = [
      if (first != null && first.isNotEmpty) first,
      if (second != null && second.isNotEmpty) second,
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  String? _descriptionFor(Transaction t) {
    final details = t.description;
    if (t.dateConfirmed) return details;
    final dt = DateTime.fromMillisecondsSinceEpoch(t.date.toInt());
    final estimated = context.l10n.estimated(
      formatWeekday(dt, context.localeName),
    );
    return _joinDescriptions(estimated, details);
  }
}

sealed class _ListEntry {
  const _ListEntry();
}

class _HeaderEntry extends _ListEntry {
  const _HeaderEntry({required this.label});
  final String label;
}

class _TxnEntry extends _ListEntry {
  const _TxnEntry({
    required this.transactionId,
    required this.title,
    required this.type,
    required this.amountCents,
    required this.currency,
    required this.dateConfirmed,
    required this.visualIdentities,
    this.transferSide,
    this.description,
  });

  factory _TxnEntry.fromTransaction(
    Transaction transaction, {
    required int amountCents,
    required List<TransactionRowVisualIdentity> visualIdentities,
    String? description,
  }) => _TxnEntry(
    transactionId: transaction.id,
    title: transaction.name,
    type: transaction.type,
    amountCents: amountCents,
    currency: transaction.currency,
    dateConfirmed: transaction.dateConfirmed,
    description: description,
    visualIdentities: visualIdentities,
    transferSide: null,
  );

  final String transactionId;
  final String title;

  /// Wire transaction type ([TxnType.wire]); gates name localization so only
  /// generated balance-adjustment names are translated.
  final String type;
  final int amountCents;
  final String currency;
  final bool dateConfirmed;
  final String? description;
  final List<TransactionRowVisualIdentity> visualIdentities;
  final TransactionDetailTransferSide? transferSide;
}

class _LoadingEntry extends _ListEntry {
  const _LoadingEntry();
}

class _BottomSpaceEntry extends _ListEntry {
  const _BottomSpaceEntry();
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onChanged});

  final TxnType? selected;
  final ValueChanged<TxnType?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <({TxnType? value, String label})>[
      (value: null, label: context.l10n.all),
      (value: TxnType.income, label: context.l10n.incomes),
      (value: TxnType.expense, label: context.l10n.expenses),
      (value: TxnType.transfer, label: context.l10n.transfers),
      (
        value: TxnType.balanceAdjustment,
        label: context.l10n.balanceAdjustments,
      ),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          final isSelected = option.value == selected;
          return ChoiceChip(
            label: Text(option.label),
            selected: isSelected,
            onSelected: (_) => onChanged(option.value),
            showCheckmark: false,
          );
        },
      ),
    );
  }
}
