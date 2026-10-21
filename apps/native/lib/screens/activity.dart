import 'dart:async';

import 'package:app/components/account_icons.dart';
import 'package:app/components/category_icons.dart';
import 'package:app/components/color_utils.dart';
import 'package:app/components/transaction_filters_bar.dart';
import 'package:app/components/transaction_row.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/adaptive_detail_view.dart'
    show InstantEntranceMaterialPageRoute;
import 'package:app/shared/app_navigation.dart';
import 'package:app/shared/breakpoints.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app/screens/future_movements.dart';
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

  /// Selection for the detail view — one source of truth for every window
  /// size. Expanded windows render it inline in the split pane; smaller
  /// windows present it as a REAL [MaterialPageRoute], keeping the exact
  /// platform transition, back button/gestures, and route semantics.
  String? _detailTransactionId;
  TransactionDetailTransferSide? _detailTransferSide;

  /// Pins the detail widget's Element so its State (including mid-edit
  /// fields) survives moving between the split pane, the handoff bridge, and
  /// the pushed route on window resize. The keyed widget is built somewhere
  /// in EVERY frame, which is what makes the same-frame reparenting work.
  /// Recreated per selection so a different transaction loads fresh.
  GlobalKey _detailKey = GlobalKey(debugLabel: 'activityDetail');

  /// The live mobile route, when the detail is presented as one. Nulled
  /// BEFORE a programmatic removal, so the route's completion handler can
  /// tell a user pop (clear the selection) from a resize handoff (keep it).
  MaterialPageRoute<TransactionFilter?>? _detailRoute;

  /// The new-transaction form: same machinery as the detail — one source of
  /// truth, split pane on expanded windows, a real pushed route on smaller
  /// ones, state-preserving handoffs on resize.
  bool _formOpen = false;
  GlobalKey _formKey = GlobalKey(debugLabel: 'activityForm');
  MaterialPageRoute<bool?>? _formRoute;

  /// Taken from the filter when the form opens, so changing the filter while
  /// the form sits in the split pane doesn't move its prefills.
  TransactionFormPrefill _formPrefill = const TransactionFormPrefill();

  void _openTransactionForm() {
    setState(() {
      _formOpen = true;
      _formKey = GlobalKey(debugLabel: 'activityForm');
      _formPrefill = TransactionFormPrefill.fromFilter(_filter);
      // The pane hosts one occupant at a time.
      _detailTransactionId = null;
      _detailTransferSide = null;
    });
    if (windowSizeClassOf(context) != WindowSizeClass.expanded) {
      _pushFormRoute(instant: false);
    }
  }

  void _openFutureMovements() {
    // Same shape as the home card's push: the pushed route sits above the
    // account-scoped providers, so the screen's data layer has to be
    // re-provided into it.
    final repos = context.read<AppRepositories>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Provider<AppRepositories>.value(
          value: repos,
          child: const FutureMovementsScreen(),
        ),
      ),
    );
  }

  /// Presents the form as a real route (the original mobile behavior),
  /// instant only when taking over from the split pane on window shrink.
  void _pushFormRoute({required bool instant}) {
    // Pushed routes sit above the account-scoped providers; re-provide them
    // so the route keeps using the active account's data layer. The keyed
    // form widget itself moves in/out of this wrapper on handoffs.
    final repos = context.read<AppRepositories>();
    Widget buildPage(BuildContext _) => Provider<AppRepositories>.value(
      value: repos,
      child: _buildForm(inRoute: true) ?? const SizedBox.shrink(),
    );
    final route = instant
        ? InstantEntranceMaterialPageRoute<bool?>(builder: buildPage)
        : MaterialPageRoute<bool?>(builder: buildPage);
    _formRoute = route;
    unawaited(
      Navigator.of(context).push(route).then((saved) {
        // Only a USER exit (back/cancel/save) reaches here with the route
        // still owned — a resize handoff nulls _formRoute first.
        if (!mounted || !identical(_formRoute, route)) return;
        _formRoute = null;
        setState(() => _formOpen = false);
        if (saved == true) {
          context.read<AppNavigation>().index = AppNavigation.activityTab;
        }
      }),
    );
    // Rebuild so the handoff bridge (if shown) is dropped in the same frame
    // the route claims the GlobalKey — the Element moves, State intact.
    setState(() {});
  }

  /// Route mode gets no [TransactionFormScreen.onResult], so the form pops
  /// itself with its result — the original mobile behavior, unchanged.
  Widget? _buildForm({required bool inRoute}) {
    if (!_formOpen) return null;
    return TransactionFormScreen(
      key: _formKey,
      onResult: inRoute ? null : _onFormResult,
      initialType: _formPrefill.type,
      initialAccountId: _formPrefill.accountId,
      initialDestinationAccountId: _formPrefill.destinationAccountId,
      initialCategoryId: _formPrefill.categoryId,
    );
  }

  void _onFormResult(bool saved) {
    // The list is stream-driven, so a saved transaction shows up on its own.
    setState(() => _formOpen = false);
  }

  /// Whether Activity is the tab currently on screen. Its detail and form
  /// routes are pushed on the SHARED navigator, above every tab, so a hidden
  /// Activity must own none of them — it would cover whatever tab the user is
  /// actually looking at (leave a detail or the new-transaction form open,
  /// switch to Home, shrink the window, and the route would slam over Home).
  /// Hidden, the occupant stays in the bridge — State intact, painting
  /// nothing inside the hidden tab — and is re-presented on return.
  bool get _isActiveTab =>
      context.read<AppNavigation>().index == AppNavigation.activityTab;

  /// Form counterpart of [_reconcileDetailRoute].
  void _reconcileFormRoute() {
    if (!mounted) return;
    final split = windowSizeClassOf(context) == WindowSizeClass.expanded;
    final needsRoute = !split && _formOpen && _isActiveTab;
    final route = _formRoute;
    if (needsRoute && route == null) {
      _pushFormRoute(instant: true);
    } else if (!needsRoute && route != null) {
      _formRoute = null;
      Navigator.of(context).removeRoute(route);
      setState(() {});
    }
  }

  void _openTransactionDetails(
    String transactionId, {
    TransactionDetailTransferSide? transferSide,
  }) {
    setState(() {
      if (transactionId != _detailTransactionId ||
          transferSide != _detailTransferSide) {
        _detailKey = GlobalKey(debugLabel: 'activityDetail');
      }
      _detailTransactionId = transactionId;
      _detailTransferSide = transferSide;
      // The pane hosts one occupant at a time.
      _formOpen = false;
    });
    if (windowSizeClassOf(context) != WindowSizeClass.expanded) {
      // Mobile: a real MaterialPageRoute, with the platform's own entrance
      // animation — exactly as it always behaved.
      _pushDetailRoute(instant: false);
    }
  }

  /// Presents the detail as a real route. [instant] skips the entrance
  /// animation — used only when the route takes over from the split pane on
  /// window shrink, where the content is already on screen and must simply
  /// stay in place. Popping always plays the standard animation.
  void _pushDetailRoute({required bool instant}) {
    final repos = context.read<AppRepositories>();
    final route = instant
        ? InstantEntranceMaterialPageRoute<TransactionFilter?>(
            builder: (_) => _buildRouteDetail(repos),
          )
        : MaterialPageRoute<TransactionFilter?>(
            builder: (_) => _buildRouteDetail(repos),
          );
    _detailRoute = route;
    unawaited(
      Navigator.of(context).push(route).then((result) {
        // Only a USER exit (back/gesture/delete/filter tap) reaches here with
        // the route still owned — a resize handoff nulls _detailRoute first.
        if (!mounted || !identical(_detailRoute, route)) return;
        _detailRoute = null;
        setState(() {
          _detailTransactionId = null;
          _detailTransferSide = null;
          if (result != null) {
            _filter = result;
            _resetPagination();
          }
        });
      }),
    );
    // Rebuild so the handoff bridge (if shown) is dropped in the same frame
    // the route claims the GlobalKey — the Element moves, State intact.
    setState(() {});
  }

  /// Route-mode detail: no [TransactionDetailsScreen.onResult], so the screen
  /// pops itself with its result and gets the automatic back button — the
  /// original mobile behavior, unchanged.
  Widget _buildRouteDetail(AppRepositories repos) {
    final transactionId = _detailTransactionId;
    if (transactionId == null) return const SizedBox.shrink();
    return TransactionDetailsScreen(
      key: _detailKey,
      transactionId: transactionId,
      repos: repos,
      transferSide: _detailTransferSide,
    );
  }

  /// Keeps the mobile route in sync with (window class × selection × tab
  /// visibility): pushes an instant-entrance route when the window shrinks
  /// with a detail open, removes the route without animation when the window
  /// grows into the split or Activity stops being the visible tab.
  /// Idempotent; runs post-frame, scheduled by build on mismatch.
  void _reconcileDetailRoute() {
    if (!mounted) return;
    final split = windowSizeClassOf(context) == WindowSizeClass.expanded;
    final needsRoute = !split && _detailTransactionId != null && _isActiveTab;
    final route = _detailRoute;
    if (needsRoute && route == null) {
      _pushDetailRoute(instant: true);
    } else if (!needsRoute && route != null) {
      // Null first: the route's completion handler must treat this as a
      // handoff (or a cleared selection) and not re-clear state.
      _detailRoute = null;
      Navigator.of(context).removeRoute(route);
      setState(() {});
    }
  }

  /// Close/result handler for the inline presentations (split pane and the
  /// handoff bridge): clears the selection and applies a handed-back filter.
  /// The pushed route reports through its pop result instead.
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
    _nav?.noteActivityFilterReplaced(_filter);
    _filter = widget.initialFilter;
    // Another surface asked for a filtered list: the list is the point, so
    // an open detail closes.
    _detailTransactionId = null;
    _detailTransferSide = null;
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
    _nav?.noteActivityFilterReplaced(_filter);
    setState(() {
      _filter = pending;
      _detailTransactionId = null;
      _detailTransferSide = null;
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
        // The way across to the upcoming side, which Activity otherwise gives
        // no hint of — the two lists are one timeline split at the occurrence
        // cutoff. Not behind `recurringExpense`: the cutoff applies to every
        // future-dated movement, series or not.
        IconButton(
          tooltip: context.l10n.viewFutureMovements,
          onPressed: _openFutureMovements,
          icon: const Icon(Icons.event_repeat_rounded),
        ),
        IconButton(
          tooltip: context.l10n.addTransaction,
          onPressed: _openTransactionForm,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );

    // The mobile routes follow (window class × selection × tab visibility);
    // build only schedules the sync so pushes/removals happen between frames.
    // Subscribed via select so a tab switch rebuilds and reconciles (see
    // [_isActiveTab] for why a hidden Activity owns no route).
    final isActiveTab = context.select<AppNavigation, bool>(
      (nav) => nav.index == AppNavigation.activityTab,
    );
    final needsRoute =
        !showDetailPane && _detailTransactionId != null && isActiveTab;
    if (needsRoute != (_detailRoute != null)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reconcileDetailRoute(),
      );
    }
    final needsFormRoute = !showDetailPane && _formOpen && isActiveTab;
    if (needsFormRoute != (_formRoute != null)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reconcileFormRoute(),
      );
    }

    // Build the detail ONCE per frame and inflate it in exactly one place —
    // pane, bridge, or route. Its GlobalKey then reparents the live Element
    // on every handoff, so its State (including mid-edit fields) survives
    // window resizes in both directions.
    final detail = _buildDetail(repos);

    final Widget body;
    if (showDetailPane) {
      // Split layout: the Activity app bar belongs to the list column only,
      // and the detail column brings its own (TransactionDetailsScreen's
      // Scaffold), so the divider runs the full height of the body.
      //
      // A pane occupant may only claim its GlobalKey once its mobile route
      // has released it: in the frame right after a grow — before the
      // post-frame handoff removes the route — inflating it here would steal
      // the Element out of the still-visible route (duplicate-key assert,
      // hole in the route's page). The route covers the window that frame,
      // so the fallback is never actually seen. The form wins the pane; the
      // open methods enforce one occupant at a time anyway.
      final formPane = _formOpen && _formRoute == null
          ? _buildForm(inRoute: false)
          : null;
      final pane = _detailRoute == null ? detail : null;
      body = Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: Scaffold(appBar: appBar, body: list),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(child: formPane ?? pane ?? _buildDetailPlaceholder()),
            ],
          ),
        ),
      );
    } else {
      // Small windows: detail and form live in REAL pushed routes (see
      // _pushDetailRoute / _pushFormRoute). The bridges below render only
      // during handoff frames — after a shrink, before the route claims the
      // GlobalKey — so the content is built somewhere in every frame and its
      // State survives. Each paints the same page its route shows, so the
      // swap is invisible. User-initiated opens push synchronously, so no
      // bridge frame exists for them.
      final bridge = _detailRoute == null ? detail : null;
      final formBridge = _formOpen && _formRoute == null
          ? _buildForm(inRoute: false)
          : null;
      body = Stack(
        fit: StackFit.expand,
        children: [
          Scaffold(
            appBar: appBar,
            body: SafeArea(child: list),
          ),
          ?bridge,
          ?formBridge,
        ],
      );
    }

    // The routes handle system back natively. This safety net covers only
    // the transient bridge frames, and only while Activity is the visible
    // tab: back then closes the bridged occupant instead of leaving the app.
    final detailBridging =
        !showDetailPane && detail != null && _detailRoute == null;
    final formBridging = !showDetailPane && _formOpen && _formRoute == null;
    final interceptPop = (detailBridging || formBridging) && isActiveTab;
    return PopScope(
      canPop: !interceptPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (formBridging) {
          _onFormResult(false);
        } else {
          _onDetailResult(null);
        }
      },
      child: body,
    );
  }

  Widget? _buildDetail(AppRepositories repos) {
    final transactionId = _detailTransactionId;
    if (transactionId == null) return null;
    return TransactionDetailsScreen(
      key: _detailKey,
      transactionId: transactionId,
      repos: repos,
      transferSide: _detailTransferSide,
      onResult: _onDetailResult,
    );
  }

  Widget _buildDetailPlaceholder() {
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
          label: context.l10n.accountIdentity(account.name),
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
            label: context.l10n.categoryIdentity(category.name),
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
