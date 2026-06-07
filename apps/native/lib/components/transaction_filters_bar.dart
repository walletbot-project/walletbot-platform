import 'package:app/database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Immutable filter state used by the activity list. The bar widget below is
/// purely controlled — it never owns this state, so callers can persist or
/// share it freely.
class TransactionFilters {
  const TransactionFilters({
    this.searchQuery = '',
    this.categoryIds = const {},
    this.accountIds = const {},
    this.tagIds = const {},
    this.dateFrom,
    this.dateTo,
  });

  final String searchQuery;
  final Set<String> categoryIds;
  final Set<String> accountIds;
  final Set<String> tagIds;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  bool get hasAdvancedFilters =>
      categoryIds.isNotEmpty ||
      accountIds.isNotEmpty ||
      tagIds.isNotEmpty ||
      dateFrom != null ||
      dateTo != null;

  int get advancedFilterCount {
    var count = 0;
    if (categoryIds.isNotEmpty) count++;
    if (accountIds.isNotEmpty) count++;
    if (tagIds.isNotEmpty) count++;
    if (dateFrom != null || dateTo != null) count++;
    return count;
  }

  /// `dateFrom`/`dateTo` use nullable thunks so callers can distinguish
  /// "keep existing" from "set to null".
  TransactionFilters copyWith({
    String? searchQuery,
    Set<String>? categoryIds,
    Set<String>? accountIds,
    Set<String>? tagIds,
    DateTime? Function()? dateFrom,
    DateTime? Function()? dateTo,
  }) {
    return TransactionFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      categoryIds: categoryIds ?? this.categoryIds,
      accountIds: accountIds ?? this.accountIds,
      tagIds: tagIds ?? this.tagIds,
      dateFrom: dateFrom != null ? dateFrom() : this.dateFrom,
      dateTo: dateTo != null ? dateTo() : this.dateTo,
    );
  }
}

class TransactionFiltersBar extends StatefulWidget {
  const TransactionFiltersBar({
    super.key,
    required this.filters,
    required this.onChanged,
  });

  final TransactionFilters filters;
  final ValueChanged<TransactionFilters> onChanged;

  @override
  State<TransactionFiltersBar> createState() => _TransactionFiltersBarState();
}

class _TransactionFiltersBarState extends State<TransactionFiltersBar> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.filters.searchQuery);
  }

  @override
  void didUpdateWidget(TransactionFiltersBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only resync the field if the parent reset it from the outside —
    // comparing against the controller's current text avoids cursor jumps
    // when the user is typing.
    if (widget.filters.searchQuery != _searchController.text) {
      _searchController.text = widget.filters.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openSheet() async {
    // The sheet is pushed as a new route, which sits below the Provider<AppDatabase>
    // in the inherited-widget tree. Capture the db here (where it's visible) and
    // hand it down explicitly to the sheet.
    final db = context.read<AppDatabase>();
    final result = await showModalBottomSheet<TransactionFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FiltersSheet(initial: widget.filters, db: db),
    );
    if (result != null) widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => widget.onChanged(
                    widget.filters.copyWith(searchQuery: value),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Buscar',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(32),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(32),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(32),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _FilterButton(
                count: widget.filters.advancedFilterCount,
                onTap: _openSheet,
              ),
            ],
          ),
        ),
        if (widget.filters.hasAdvancedFilters)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _ActiveFilterChips(
              filters: widget.filters,
              onChanged: widget.onChanged,
            ),
          ),
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton.filledTonal(
          onPressed: onTap,
          icon: const Icon(Icons.tune_rounded),
        ),
        if (count > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Center(
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({required this.filters, required this.onChanged});

  final TransactionFilters filters;
  final ValueChanged<TransactionFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();
    final chips = <Widget>[];

    if (filters.dateFrom != null || filters.dateTo != null) {
      chips.add(
        InputChip(
          label: Text(_formatDateRange(filters.dateFrom, filters.dateTo)),
          onDeleted: () => onChanged(
            filters.copyWith(dateFrom: () => null, dateTo: () => null),
          ),
        ),
      );
    }

    if (filters.accountIds.isNotEmpty) {
      final ids = filters.accountIds.toList();
      chips.add(
        _NamedFilterChip(
          stream:
              (db.select(db.accounts)
                    ..where((a) => a.archived.equals(false))
                    ..where((a) => a.id.isIn(ids)))
                  .watch()
                  .map((rows) => rows.map((r) => r.name).toList()),
          fallback: 'cuentas',
          onDeleted: () => onChanged(filters.copyWith(accountIds: const {})),
        ),
      );
    }

    if (filters.categoryIds.isNotEmpty) {
      final ids = filters.categoryIds.toList();
      chips.add(
        _NamedFilterChip(
          stream:
              (db.select(db.categories)
                    ..where((c) => c.archived.equals(false))
                    ..where((c) => c.id.isIn(ids)))
                  .watch()
                  .map((rows) => rows.map((r) => r.name).toList()),
          fallback: 'categorías',
          onDeleted: () => onChanged(filters.copyWith(categoryIds: const {})),
        ),
      );
    }

    if (filters.tagIds.isNotEmpty) {
      final ids = filters.tagIds.toList();
      chips.add(
        _NamedFilterChip(
          stream:
              (db.select(db.tags)
                    ..where((t) => t.archived.equals(false))
                    ..where((t) => t.id.isIn(ids)))
                  .watch()
                  .map((rows) => rows.map((r) => r.name).toList()),
          fallback: 'tags',
          onDeleted: () => onChanged(filters.copyWith(tagIds: const {})),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            chips[i],
          ],
        ],
      ),
    );
  }
}

class _NamedFilterChip extends StatelessWidget {
  const _NamedFilterChip({
    required this.stream,
    required this.fallback,
    required this.onDeleted,
  });

  final Stream<List<String>> stream;
  final String fallback;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: stream,
      builder: (context, snapshot) {
        final names = snapshot.data;
        final label = (names == null || names.isEmpty)
            ? fallback
            : (names.length <= 2
                  ? names.join(', ')
                  : '${names.take(2).join(', ')} +${names.length - 2}');
        return InputChip(label: Text(label), onDeleted: onDeleted);
      },
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.initial, required this.db});

  final TransactionFilters initial;
  final AppDatabase db;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late TransactionFilters _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = (_draft.dateFrom != null && _draft.dateTo != null)
        ? DateTimeRange(start: _draft.dateFrom!, end: _draft.dateTo!)
        : null;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5),
      initialDateRange: initial,
    );
    if (picked == null) return;
    setState(() {
      _draft = _draft.copyWith(
        dateFrom: () => picked.start,
        dateTo: () => picked.end,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filtros',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _draft = const TransactionFilters()),
                    child: const Text('Limpiar'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  const _SectionTitle('Rango de fechas'),
                  const SizedBox(height: 8),
                  _DateRangeRow(
                    from: _draft.dateFrom,
                    to: _draft.dateTo,
                    onPick: _pickDateRange,
                    onClear: (_draft.dateFrom == null && _draft.dateTo == null)
                        ? null
                        : () => setState(
                            () => _draft = _draft.copyWith(
                              dateFrom: () => null,
                              dateTo: () => null,
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle('Cuentas'),
                  const SizedBox(height: 8),
                  _PickerSection<Account>(
                    stream:
                        (widget.db.select(widget.db.accounts)
                              ..where((a) => a.archived.equals(false)))
                            .watch(),
                    selectedIds: _draft.accountIds,
                    idOf: (a) => a.id,
                    labelOf: (a) => a.name,
                    onChanged: (ids) => setState(
                      () => _draft = _draft.copyWith(accountIds: ids),
                    ),
                    emptyText: 'No hay cuentas',
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle('Categorías'),
                  const SizedBox(height: 8),
                  _PickerSection<Category>(
                    stream:
                        (widget.db.select(widget.db.categories)
                              ..where((c) => c.archived.equals(false)))
                            .watch(),
                    selectedIds: _draft.categoryIds,
                    idOf: (c) => c.id,
                    labelOf: (c) => c.name,
                    onChanged: (ids) => setState(
                      () => _draft = _draft.copyWith(categoryIds: ids),
                    ),
                    emptyText: 'No hay categorías',
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle('Tags'),
                  const SizedBox(height: 8),
                  _PickerSection<Tag>(
                    stream:
                        (widget.db.select(widget.db.tags)
                              ..where((t) => t.archived.equals(false)))
                            .watch(),
                    selectedIds: _draft.tagIds,
                    idOf: (t) => t.id,
                    labelOf: (t) => t.name,
                    onChanged: (ids) =>
                        setState(() => _draft = _draft.copyWith(tagIds: ids)),
                    emptyText: 'No hay tags',
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, _draft),
                        child: const Text('Aplicar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
  }
}

class _DateRangeRow extends StatelessWidget {
  const _DateRangeRow({
    required this.from,
    required this.to,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? from;
  final DateTime? to;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final label = (from == null && to == null)
        ? 'Seleccionar rango'
        : _formatDateRange(from, to);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text(label, overflow: TextOverflow.ellipsis),
          ),
        ),
        if (onClear != null) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: onClear,
            tooltip: 'Limpiar',
          ),
        ],
      ],
    );
  }
}

class _PickerSection<T> extends StatelessWidget {
  const _PickerSection({
    required this.stream,
    required this.selectedIds,
    required this.idOf,
    required this.labelOf,
    required this.onChanged,
    required this.emptyText,
  });

  final Stream<List<T>> stream;
  final Set<String> selectedIds;
  final String Function(T) idOf;
  final String Function(T) labelOf;
  final ValueChanged<Set<String>> onChanged;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<T>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          );
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return Text(
            emptyText,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              FilterChip(
                label: Text(labelOf(item)),
                selected: selectedIds.contains(idOf(item)),
                onSelected: (_) {
                  final next = Set<String>.from(selectedIds);
                  final id = idOf(item);
                  if (!next.add(id)) next.remove(id);
                  onChanged(next);
                },
              ),
          ],
        );
      },
    );
  }
}

String _formatDateRange(DateTime? from, DateTime? to) {
  String fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  if (from != null && to != null) return '${fmt(from)} – ${fmt(to)}';
  if (from != null) return 'Desde ${fmt(from)}';
  if (to != null) return 'Hasta ${fmt(to)}';
  return '';
}
