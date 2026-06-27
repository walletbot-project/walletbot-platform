import 'package:app/components/transaction_filters_bar.dart';
import 'package:app/components/transaction_row.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/shared/app_navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app/screens/transaction_form.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const _pageSize = 50;
  static const _spanishWeekdays = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  final _scrollController = ScrollController();

  AppNavigation? _nav;

  TransactionFilter _filter = const TransactionFilter();
  int _limit = _pageSize;

  /// Tracks the size of the most recent rendered slice so the scroll listener
  /// can tell whether the current page is full (more might exist) or short
  /// (we've reached the end).
  int _lastRenderedCount = 0;

  Future<void> _openTransactionForm() async {
    // Pushed routes sit above the account-scoped providers; re-provide them
    // so the new route keeps using the active account's data layer.
    final repos = context.read<AppRepositories>();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Provider<AppRepositories>.value(
          value: repos,
          child: const TransactionFormScreen(),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Actividad'),
        actions: [
          IconButton(
            tooltip: 'Anadir movimiento',
            onPressed: _openTransactionForm,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
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
                selected: _filter.types.length == 1
                    ? _filter.types.single
                    : null,
                onChanged: _updateTypeChip,
              ),
            ),
            StreamBuilder<List<Transaction>>(
              stream: repos.transactions.watch(_filter, limit: _limit),
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
                          'Error al cargar transacciones: ${snapshot.error}',
                        ),
                      ),
                    ),
                  );
                }

                final items = snapshot.data ?? const <Transaction>[];
                _lastRenderedCount = items.length;

                if (items.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No hay transacciones'),
                      ),
                    ),
                  );
                }

                final hasMore = items.length >= _limit;
                final entries = _buildListEntries(items, hasMore: hasMore);

                return SliverList.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      _buildEntry(context, entries[index]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<_ListEntry> _buildListEntries(
    List<Transaction> items, {
    required bool hasMore,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entries = <_ListEntry>[];

    DateTime? currentDay;
    for (final t in items) {
      // Group by creation time so the day headers stay contiguous with the
      // creation-order sorting above.
      final dt = DateTime.fromMillisecondsSinceEpoch(t.createdAt.toInt());
      final day = DateTime(dt.year, dt.month, dt.day);
      if (currentDay == null || day != currentDay) {
        entries.add(_HeaderEntry(label: _sectionLabel(day, today)));
        currentDay = day;
      }
      if (t.type == 'transfer') {
        entries.addAll(_transferEntries(t));
      } else {
        entries.add(
          _TxnEntry.fromTransaction(
            t,
            amountCents: _signedAmountCents(t),
            description: _descriptionFor(t),
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
        :final title,
        :final amountCents,
        :final currency,
        :final dateConfirmed,
        :final description,
      ):
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TransactionRow(
            title: title,
            amountCents: amountCents,
            currency: currency,
            dateCheck: dateConfirmed,
            description: description,
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
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    if (diff > 1 && diff < 7) return _spanishWeekdays[day.weekday - 1];
    return '${day.day.toString().padLeft(2, '0')}/'
        '${day.month.toString().padLeft(2, '0')}/${day.year}';
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

  List<_TxnEntry> _transferEntries(Transaction t) {
    final description = _descriptionFor(t);
    final sourceAmount = -t.amount.toInt().abs();
    final destinationAmount = (t.toAmount ?? t.amount).toInt().abs();
    return [
      _TxnEntry(
        title: 'Transferencia enviada',
        amountCents: sourceAmount,
        currency: t.currency,
        dateConfirmed: t.dateConfirmed,
        description: description,
      ),
      _TxnEntry(
        title: 'Transferencia recibida',
        amountCents: destinationAmount,
        currency: t.toCurrency ?? t.currency,
        dateConfirmed: t.dateConfirmed,
        description: description,
      ),
    ];
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
    final estimated = '${_spanishWeekdays[dt.weekday - 1]} (estimado)';
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
    required this.title,
    required this.amountCents,
    required this.currency,
    required this.dateConfirmed,
    this.description,
  });

  factory _TxnEntry.fromTransaction(
    Transaction transaction, {
    required int amountCents,
    String? description,
  }) => _TxnEntry(
    title: transaction.name,
    amountCents: amountCents,
    currency: transaction.currency,
    dateConfirmed: transaction.dateConfirmed,
    description: description,
  );

  final String title;
  final int amountCents;
  final String currency;
  final bool dateConfirmed;
  final String? description;
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
    const options = <({TxnType? value, String label})>[
      (value: null, label: 'Todos'),
      (value: TxnType.income, label: 'Ingresos'),
      (value: TxnType.expense, label: 'Gastos'),
      (value: TxnType.transfer, label: 'Transferencias'),
      (value: TxnType.balanceAdjustment, label: 'Ajustes'),
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
