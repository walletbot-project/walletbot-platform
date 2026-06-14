import 'package:app/components/filter_sheet.dart';
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
    // The unified filter sheet owns every dimension; the activity bar keeps
    // type (chip row) and text (search field), so those sections are hidden
    // here to avoid duplicate controls.
    final result = await showFilterSheet(
      context,
      initial: widget.filter,
      hiddenSections: const {FilterSection.type, FilterSection.text},
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
                  onChanged: (value) =>
                      widget.onChanged(widget.filter.copyWith(search: value)),
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
          stream: _namesOf(
            repos.accounts.watchActive(),
            filter.accountIds,
            (Account a) => a.id,
            (Account a) => a.name,
          ),
          fallback: 'cuentas',
          onDeleted: () => onChanged(filter.copyWith(accountIds: const {})),
        ),
      );
    }

    if (filter.categoryIds.isNotEmpty) {
      chips.add(
        _NamedFilterChip(
          stream: _namesOf(
            repos.categories.watchActive(),
            filter.categoryIds,
            (Category c) => c.id,
            (Category c) => c.name,
          ),
          fallback: 'categorías',
          onDeleted: () => onChanged(filter.copyWith(categoryIds: const {})),
        ),
      );
    }

    if (filter.tagIds.isNotEmpty) {
      chips.add(
        _NamedFilterChip(
          stream: _namesOf(
            repos.tags.watchActive(),
            filter.tagIds,
            (Tag t) => t.id,
            (Tag t) => t.name,
          ),
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
      (rows) => rows.where((r) => ids.contains(idOf(r))).map(nameOf).toList(),
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

String _formatDateRange(DateTime from, DateTime to) {
  String fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  return '${fmt(from)} – ${fmt(to)}';
}
