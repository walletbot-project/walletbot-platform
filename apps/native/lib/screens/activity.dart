import 'package:app/components/transaction_filters_bar.dart';
import 'package:app/components/transaction_row.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const _pageSize = 50;
  static const _spanishWeekdays = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

  final _scrollController = ScrollController();

  TransactionFilters _filters = const TransactionFilters();
  String? _filterType;
  int _limit = _pageSize;

  /// Tracks the size of the most recent rendered slice so the scroll listener
  /// can tell whether the current page is full (more might exist) or short
  /// (we've reached the end).
  int _lastRenderedCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
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

  void _updateFilter(String? value) {
    setState(() {
      _filterType = value;
      _resetPagination();
    });
  }

  void _onFiltersChanged(TransactionFilters next) {
    setState(() {
      _filters = next;
      _resetPagination();
    });
  }

  Stream<List<Transaction>> _watchTransactions(AppDatabase db) {
    final query = db.select(db.transactions)..where((t) => t.archived.equals(false));

    final type = _filterType;
    if (type != null) {
      query.where((t) => t.type.equals(type));
    }

    final search = _filters.searchQuery.trim();
    if (search.isNotEmpty) {
      final pattern = '%${search.toLowerCase()}%';
      query.where((t) => t.name.lower().like(pattern));
    }

    if (_filters.categoryIds.isNotEmpty) {
      final ids = _filters.categoryIds.toList();
      query.where((t) => t.categoryId.isIn(ids));
    }

    if (_filters.accountIds.isNotEmpty) {
      final ids = _filters.accountIds.toList();
      query.where((t) => t.accountId.isIn(ids));
    }

    if (_filters.dateFrom != null) {
      final ms = BigInt.from(_filters.dateFrom!.millisecondsSinceEpoch);
      query.where((t) => t.date.isBiggerOrEqualValue(ms));
    }
    if (_filters.dateTo != null) {
      // Inclusive end of day.
      final endOfDay = DateTime(_filters.dateTo!.year, _filters.dateTo!.month, _filters.dateTo!.day + 1);
      final ms = BigInt.from(endOfDay.millisecondsSinceEpoch);
      query.where((t) => t.date.isSmallerThanValue(ms));
    }

    if (_filters.tagIds.isNotEmpty) {
      final tagIds = _filters.tagIds.toList();
      final taggedTxnIds = db.selectOnly(db.transactionTags)
        ..addColumns([db.transactionTags.transactionId])
        ..where(db.transactionTags.tagId.isIn(tagIds));
      query.where((t) => t.id.isInQuery(taggedTxnIds));
    }

    // Order strictly by creation time (newest first), regardless of the
    // (possibly estimated) transaction date.
    query
      ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)])
      ..limit(_limit);
    return query.watch();
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();

    return Scaffold(
      appBar: AppBar(title: const Text('Actividad')),
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverToBoxAdapter(
              child: TransactionFiltersBar(filters: _filters, onChanged: _onFiltersChanged),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(
              child: _FilterChips(selected: _filterType, onChanged: _updateFilter),
            ),
            StreamBuilder<List<Transaction>>(
              stream: _watchTransactions(db),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(padding: const EdgeInsets.all(32), child: Text('Error al cargar transacciones: ${snapshot.error}')),
                    ),
                  );
                }

                final items = snapshot.data ?? const <Transaction>[];
                _lastRenderedCount = items.length;

                if (items.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(padding: EdgeInsets.all(32), child: Text('No hay transacciones')),
                    ),
                  );
                }

                final hasMore = items.length >= _limit;
                final entries = _buildListEntries(items, hasMore: hasMore);

                return SliverList.builder(itemCount: entries.length, itemBuilder: (context, index) => _buildEntry(context, entries[index]));
              },
            ),
          ],
        ),
      ),
    );
  }

  List<_ListEntry> _buildListEntries(List<Transaction> items, {required bool hasMore}) {
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
      entries.add(_TxnEntry(transaction: t));
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
          child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        );
      case _TxnEntry(:final transaction):
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TransactionRow(
            title: transaction.name,
            amountCents: _signedAmountCents(transaction),
            dateCheck: transaction.dateConfirmed,
            description: _descriptionFor(transaction),
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

  String? _descriptionFor(Transaction t) {
    if (t.dateConfirmed) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(t.date.toInt());
    return '${_spanishWeekdays[dt.weekday - 1]} (estimado)';
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
  const _TxnEntry({required this.transaction});
  final Transaction transaction;
}

class _LoadingEntry extends _ListEntry {
  const _LoadingEntry();
}

class _BottomSpaceEntry extends _ListEntry {
  const _BottomSpaceEntry();
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = <({String? value, String label})>[
      (value: null, label: 'Todos'),
      (value: 'income', label: 'Ingresos'),
      (value: 'expense', label: 'Gastos'),
      (value: 'transfer', label: 'Transferencias'),
      (value: 'balance_adjustment', label: 'Ajustes'),
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
