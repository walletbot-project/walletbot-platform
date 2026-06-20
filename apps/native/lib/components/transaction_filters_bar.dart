import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Number of advanced-filter chip groups shown by the bar (search and type
/// chips live elsewhere in the activity screen).
int _advancedFilterCount(TransactionFilter f) {
  var count = 0;
  if (f.categoryIds.isNotEmpty) count++;
  if (f.accountIds.isNotEmpty) count++;
  if (f.tagIds.isNotEmpty) count++;
  if (f.dateRange != null || f.datePreset != null) count++;
  return count;
}

bool _hasAdvancedFilters(TransactionFilter f) => _advancedFilterCount(f) > 0;

/// Search bar + advanced-filter sheet over the unified [TransactionFilter].
/// Purely controlled — it never owns the filter state, so callers can persist
/// or share it freely.
class TransactionFiltersBar extends StatefulWidget {
  const TransactionFiltersBar({
    super.key,
    required this.filter,
    required this.onChanged,
  });

  final TransactionFilter filter;
  final ValueChanged<TransactionFilter> onChanged;

  @override
  State<TransactionFiltersBar> createState() => _TransactionFiltersBarState();
}

class _TransactionFiltersBarState extends State<TransactionFiltersBar> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.filter.search ?? '');
  }

  @override
  void didUpdateWidget(TransactionFiltersBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only resync the field if the parent reset it from the outside —
    // comparing against the controller's current text avoids cursor jumps
    // when the user is typing.
    final search = widget.filter.search ?? '';
    if (search != _searchController.text) {
      _searchController.text = search;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openSheet() async {
    // The sheet is pushed as a new route, which sits below the account-scoped
    // providers in the inherited-widget tree. Capture the repositories here
    // (where they're visible) and hand them down explicitly.
    final repos = context.read<AppRepositories>();
    final result = await showModalBottomSheet<TransactionFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FiltersSheet(initial: widget.filter, repos: repos),
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
                    widget.filter.copyWith(search: value),
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
                count: _advancedFilterCount(widget.filter),
                onTap: _openSheet,
              ),
            ],
          ),
        ),
        if (_hasAdvancedFilters(widget.filter))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _ActiveFilterChips(
              filter: widget.filter,
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
  const _ActiveFilterChips({required this.filter, required this.onChanged});

  final TransactionFilter filter;
  final ValueChanged<TransactionFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final repos = context.read<AppRepositories>();
    final chips = <Widget>[];

    final range = filter.dateRange;
    if (range != null) {
      chips.add(
        InputChip(
          label: Text(_formatDateRange(range.start, range.end)),
          onDeleted: () => onChanged(filter.copyWith(clearDateRange: true)),
        ),
      );
    } else if (filter.datePreset != null) {
      chips.add(
        InputChip(
          label: Text(filter.datePreset!.label),
          onDeleted: () => onChanged(filter.copyWith(clearDatePreset: true)),
        ),
      );
    }

    if (filter.accountIds.isNotEmpty) {
      chips.add(
        _NamedFilterChip(
          stream: _namesOf(repos.accounts.watchActive(), filter.accountIds,
              (Account a) => a.id, (Account a) => a.name),
          fallback: 'cuentas',
          onDeleted: () => onChanged(filter.copyWith(accountIds: const {})),
        ),
      );
    }

    if (filter.categoryIds.isNotEmpty) {
      chips.add(
        _NamedFilterChip(
          stream: _namesOf(repos.categories.watchActive(), filter.categoryIds,
              (Category c) => c.id, (Category c) => c.name),
          fallback: 'categorías',
          onDeleted: () => onChanged(filter.copyWith(categoryIds: const {})),
        ),
      );
    }

    if (filter.tagIds.isNotEmpty) {
      chips.add(
        _NamedFilterChip(
          stream: _namesOf(repos.tags.watchActive(), filter.tagIds,
              (Tag t) => t.id, (Tag t) => t.name),
          fallback: 'tags',
          onDeleted: () => onChanged(filter.copyWith(tagIds: const {})),
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

  Stream<List<String>> _namesOf<T>(
    Stream<List<T>> source,
    Set<String> ids,
    String Function(T) idOf,
    String Function(T) nameOf,
  ) {
    return source.map(
      (rows) =>
          rows.where((r) => ids.contains(idOf(r))).map(nameOf).toList(),
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
  const _FiltersSheet({required this.initial, required this.repos});

  final TransactionFilter initial;
  final AppRepositories repos;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late TransactionFilter _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _draft.dateRange,
    );
    if (picked == null) return;
    setState(() {
      _draft = _draft.copyWith(dateRange: picked, clearDatePreset: true);
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
                    onPressed: () => setState(
                      () => _draft = TransactionFilter(
                        // The sheet only edits the advanced dimensions; keep
                        // the ones owned by the activity screen.
                        types: _draft.types,
                        status: _draft.status,
                        search: _draft.search,
                      ),
                    ),
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
                    range: _draft.dateRange,
                    onPick: _pickDateRange,
                    onClear: _draft.dateRange == null
                        ? null
                        : () => setState(
                            () => _draft =
                                _draft.copyWith(clearDateRange: true),
                          ),
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle('Cuentas'),
                  const SizedBox(height: 8),
                  _PickerSection<Account>(
                    stream: widget.repos.accounts.watchActive(),
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
                    stream: widget.repos.categories.watchActive(),
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
                    stream: widget.repos.tags.watchActive(),
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
    required this.range,
    required this.onPick,
    required this.onClear,
  });

  final DateTimeRange? range;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final label = range == null
        ? 'Seleccionar rango'
        : _formatDateRange(range!.start, range!.end);
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

String _formatDateRange(DateTime from, DateTime to) {
  String fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  return '${fmt(from)} – ${fmt(to)}';
}
