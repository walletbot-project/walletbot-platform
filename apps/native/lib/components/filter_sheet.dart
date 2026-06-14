import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart' show ReadContext;

// The filter model lives in the data layer (it drives the shared transaction
// query); re-exported here so existing imports keep working.
export 'package:app/data/models/transaction_filter.dart';

/// Dimensions the sheet can render. Callers may hide the ones they own
/// elsewhere — the activity screen, for example, keeps [FilterSection.type]
/// and [FilterSection.text] in its own bar, so it hides them here.
enum FilterSection {
  type,
  status,
  date,
  accounts,
  categories,
  tags,
  currency,
  amount,
  text,
}

/// Options loaded from local Drift for the selectable dimensions.
class _FilterOptions {
  const _FilterOptions({
    required this.accounts,
    required this.categories,
    required this.tags,
    required this.currencies,
  });

  final List<Account> accounts;
  final List<Category> categories;
  final List<Tag> tags;
  final List<String> currencies;
}

enum _FilterEditorMode { simple, advanced }

/// Opens the filter editor as a draggable bottom sheet. Resolves to the edited
/// [TransactionFilter] when the user taps "Aplicar", or `null` if dismissed.
///
/// Pass [hiddenSections] to suppress dimensions the caller edits elsewhere
/// (e.g. the activity bar owns type + text). Hidden sections keep their
/// incoming values on both apply and "Limpiar".
Future<TransactionFilter?> showFilterSheet(
  BuildContext context, {
  TransactionFilter initial = const TransactionFilter(),
  Set<FilterSection> hiddenSections = const {},
  AppRepositories? repos,
}) {
  // Read the repositories from the *calling* context: the modal route is
  // pushed by a Navigator that sits above the account-scoped providers, so
  // the sheet's own context can't reach them. Callers already inside such a
  // modal (e.g. the add-widget sheet) pass [repos] in directly.
  final resolvedRepos = repos ?? context.read<AppRepositories>();
  return showModalBottomSheet<TransactionFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => FilterSheet(
      repos: resolvedRepos,
      initial: initial,
      hiddenSections: hiddenSections,
    ),
  );
}

/// Simple-mode filter editor. Reads its option lists from the data layer and
/// returns the assembled [TransactionFilter] via `Navigator.pop`.
class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.repos,
    this.initial = const TransactionFilter(),
    this.hiddenSections = const {},
  });

  final AppRepositories repos;
  final TransactionFilter initial;
  final Set<FilterSection> hiddenSections;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late Future<_FilterOptions> _optionsFuture;
  late _FilterEditorMode _mode;
  late FilterGroup _advancedRoot;

  late Set<TxnType> _types;
  late TxnStatus? _status;
  late DatePreset? _datePreset;
  late DateTimeRange? _dateRange;
  late Set<String> _accountIds;
  late AccountDirection _accountDirection;
  late Set<String> _categoryIds;
  late Set<String> _tagIds;
  late TagMatch _tagMatch;
  late bool _includeSubtags;
  late String? _currency;

  late final TextEditingController _amountMinController;
  late final TextEditingController _amountMaxController;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    _mode = f.isAdvanced
        ? _FilterEditorMode.advanced
        : _FilterEditorMode.simple;
    _advancedRoot = f.rootGroup;
    _types = {...f.types};
    _status = f.status;
    _datePreset = f.datePreset;
    _dateRange = f.dateRange;
    _accountIds = {...f.accountIds};
    _accountDirection = f.accountDirection;
    _categoryIds = {...f.categoryIds};
    _tagIds = {...f.tagIds};
    _tagMatch = f.tagMatch;
    _includeSubtags = f.includeSubtags;
    _currency = f.currency;

    _amountMinController = TextEditingController(
      text: f.amountMinCents == null ? '' : _centsToText(f.amountMinCents!),
    );
    _amountMaxController = TextEditingController(
      text: f.amountMaxCents == null ? '' : _centsToText(f.amountMaxCents!),
    );
    _searchController = TextEditingController(text: f.search ?? '');

    _optionsFuture = _loadOptions(widget.repos);
  }

  @override
  void dispose() {
    _amountMinController.dispose();
    _amountMaxController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<_FilterOptions> _loadOptions(AppRepositories repos) async {
    final accounts = await repos.accounts.listActive();
    final categories = await repos.categories.listActive();
    final tags = await repos.tags.listActive();

    accounts.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    categories.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    tags.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final currencies = accounts.map((a) => a.currency).toSet().toList()..sort();

    return _FilterOptions(
      accounts: accounts,
      categories: categories,
      tags: tags,
      currencies: currencies,
    );
  }

  static String _centsToText(int cents) {
    final value = cents / 100;
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  int? _textToCents(String raw) {
    final trimmed = raw.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return null;
    return (parsed * 100).round();
  }

  bool _shows(FilterSection section) =>
      !widget.hiddenSections.contains(section);

  bool get _canUseAdvanced => widget.hiddenSections.isEmpty;

  /// Clears only the dimensions this sheet actually renders — hidden sections
  /// (owned by the caller, e.g. the activity bar's type chips and search) keep
  /// their incoming values.
  void _reset() {
    setState(() {
      if (_shows(FilterSection.type)) _types = {};
      if (_shows(FilterSection.status)) _status = null;
      if (_shows(FilterSection.date)) {
        _datePreset = null;
        _dateRange = null;
      }
      if (_shows(FilterSection.accounts)) {
        _accountIds = {};
        _accountDirection = AccountDirection.either;
      }
      if (_shows(FilterSection.categories)) _categoryIds = {};
      if (_shows(FilterSection.tags)) {
        _tagIds = {};
        _tagMatch = TagMatch.any;
        _includeSubtags = false;
      }
      if (_shows(FilterSection.currency)) _currency = null;
      if (_shows(FilterSection.amount)) {
        _amountMinController.clear();
        _amountMaxController.clear();
      }
      if (_shows(FilterSection.text)) _searchController.clear();
      if (_mode == _FilterEditorMode.advanced) {
        _advancedRoot = const FilterGroup();
      }
    });
  }

  TransactionFilter _simpleFilter() {
    final hasCurrency = _currency != null;
    return TransactionFilter(
      types: _types,
      status: _status,
      datePreset: _dateRange == null ? _datePreset : null,
      dateRange: _dateRange,
      accountIds: _accountIds,
      accountDirection: _accountDirection,
      categoryIds: _categoryIds,
      tagIds: _tagIds,
      tagMatch: _tagMatch,
      includeSubtags: _includeSubtags,
      currency: _currency,
      amountMinCents: hasCurrency
          ? _textToCents(_amountMinController.text)
          : null,
      amountMaxCents: hasCurrency
          ? _textToCents(_amountMaxController.text)
          : null,
      search: _searchController.text,
    );
  }

  void _apply() {
    final filter = _mode == _FilterEditorMode.advanced
        ? TransactionFilter.advanced(_advancedRoot)
        : _simpleFilter();
    Navigator.of(context).pop(filter);
  }

  void _toggleEditorMode() {
    setState(() {
      if (_mode == _FilterEditorMode.simple) {
        _advancedRoot = _simpleFilter().rootGroup;
        _mode = _FilterEditorMode.advanced;
      } else {
        _mode = _FilterEditorMode.simple;
      }
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() {
        _dateRange = picked;
        _datePreset = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          // Lift the whole sheet above the software keyboard so the action bar
          // and the lower form fields don't get hidden behind it.
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              _Header(
                onReset: _reset,
                onClose: () => Navigator.of(context).pop(),
                canToggleMode: _canUseAdvanced,
                mode: _mode,
                onToggleMode: _toggleEditorMode,
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<_FilterOptions>(
                  future: _optionsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No se pudieron cargar las opciones de filtro.\n${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    final options = snapshot.data!;
                    if (_mode == _FilterEditorMode.advanced) {
                      return _buildAdvancedForm(scrollController, options);
                    }
                    return _buildForm(context, scrollController, options);
                  },
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
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _apply,
                          child: const Text('Aplicar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildForm(
    BuildContext context,
    ScrollController scrollController,
    _FilterOptions options,
  ) {
    final hasCurrency = _currency != null;
    if (TransactionFilter.advanced(_advancedRoot).isAdvanced &&
        _canUseAdvanced) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          _AdvancedOnlyMessage(
            onEditAdvanced: () =>
                setState(() => _mode = _FilterEditorMode.advanced),
            onReplaceSimple: () => setState(() {
              _advancedRoot = const FilterGroup();
              _mode = _FilterEditorMode.simple;
            }),
          ),
        ],
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        SizedBox(height: 16),
        if (_shows(FilterSection.type))
          _Section(
            title: 'Tipo',
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final type in TxnType.values)
                  FilterChip(
                    label: Text(type.label),
                    selected: _types.contains(type),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _types.add(type);
                      } else {
                        _types.remove(type);
                      }
                    }),
                  ),
              ],
            ),
          ),
        if (_shows(FilterSection.status))
          _Section(
            title: 'Estado',
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Cualquiera'),
                  selected: _status == null,
                  onSelected: (_) => setState(() => _status = null),
                ),
                for (final status in TxnStatus.values)
                  ChoiceChip(
                    label: Text(status.label),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
              ],
            ),
          ),
        if (_shows(FilterSection.date))
          _Section(
            title: 'Fecha',
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final preset in DatePreset.values)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: _dateRange == null && _datePreset == preset,
                    onSelected: (_) => setState(() {
                      _dateRange = null;
                      _datePreset = _datePreset == preset ? null : preset;
                    }),
                  ),
                if (_dateRange != null)
                  InputChip(
                    avatar: const Icon(Icons.event, size: 18),
                    label: Text(_formatRange(_dateRange!)),
                    onDeleted: () => setState(() => _dateRange = null),
                  )
                else
                  ActionChip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    label: const Text('Rango personalizado'),
                    onPressed: _pickDateRange,
                  ),
              ],
            ),
          ),
        if (_shows(FilterSection.accounts))
          _Section(
            title: 'Cuentas',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (options.accounts.isEmpty)
                  const _EmptyHint('No hay cuentas todavía.')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final account in options.accounts)
                        FilterChip(
                          label: Text(account.name),
                          selected: _accountIds.contains(account.id),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _accountIds.add(account.id);
                            } else {
                              _accountIds.remove(account.id);
                            }
                          }),
                        ),
                    ],
                  ),
                if (_accountIds.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SubLabel('Dirección (para transferencias)'),
                  const SizedBox(height: 4),
                  SegmentedButton<AccountDirection>(
                    showSelectedIcon: false,
                    segments: [
                      for (final dir in AccountDirection.values)
                        ButtonSegment(value: dir, label: Text(dir.label)),
                    ],
                    selected: {_accountDirection},
                    onSelectionChanged: (selection) =>
                        setState(() => _accountDirection = selection.first),
                  ),
                ],
              ],
            ),
          ),
        if (_shows(FilterSection.categories))
          _Section(
            title: 'Categorías',
            child: options.categories.isEmpty
                ? const _EmptyHint('No hay categorías todavía.')
                : Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final category in options.categories)
                        FilterChip(
                          label: Text(category.name),
                          selected: _categoryIds.contains(category.id),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _categoryIds.add(category.id);
                            } else {
                              _categoryIds.remove(category.id);
                            }
                          }),
                        ),
                    ],
                  ),
          ),
        if (_shows(FilterSection.tags))
          _Section(
            title: 'Tags',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (options.tags.isEmpty)
                  const _EmptyHint('No hay tags todavía.')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final tag in options.tags)
                        FilterChip(
                          label: Text(tag.name),
                          selected: _tagIds.contains(tag.id),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _tagIds.add(tag.id);
                            } else {
                              _tagIds.remove(tag.id);
                            }
                          }),
                        ),
                    ],
                  ),
                if (_tagIds.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _SubLabel('Coincidencia'),
                      const SizedBox(width: 12),
                      SegmentedButton<TagMatch>(
                        showSelectedIcon: false,
                        segments: [
                          for (final match in TagMatch.values)
                            ButtonSegment(
                              value: match,
                              label: Text(match.label),
                            ),
                        ],
                        selected: {_tagMatch},
                        onSelectionChanged: (selection) =>
                            setState(() => _tagMatch = selection.first),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Incluir subetiquetas'),
                    value: _includeSubtags,
                    onChanged: (value) =>
                        setState(() => _includeSubtags = value),
                  ),
                ],
              ],
            ),
          ),
        if (_shows(FilterSection.currency))
          _Section(
            title: 'Moneda',
            child: options.currencies.isEmpty
                ? const _EmptyHint('No hay monedas todavía.')
                : Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final currency in options.currencies)
                        ChoiceChip(
                          label: Text(currency),
                          selected: _currency == currency,
                          onSelected: (selected) => setState(() {
                            _currency = selected ? currency : null;
                          }),
                        ),
                    ],
                  ),
          ),
        if (_shows(FilterSection.amount))
          _Section(
            title: 'Monto',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasCurrency)
                  const _EmptyHint(
                    'Seleccioná una moneda para filtrar por monto.',
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _amountMinController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Mín',
                            prefixText: '$_currency ',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _amountMaxController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Máx',
                            prefixText: '$_currency ',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        if (_shows(FilterSection.text))
          _Section(
            title: 'Texto',
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Buscar nombre o descripción…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
      ],
    );
  }

  String _formatRange(DateTimeRange range) {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '${fmt(range.start)} → ${fmt(range.end)}';
  }

  Widget _buildAdvancedForm(
    ScrollController scrollController,
    _FilterOptions options,
  ) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        _GroupEditor(
          group: _advancedRoot,
          options: options,
          depth: 0,
          onChanged: (group) => setState(() => _advancedRoot = group),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onReset,
    required this.onClose,
    required this.canToggleMode,
    required this.mode,
    required this.onToggleMode,
  });

  final VoidCallback onReset;
  final VoidCallback onClose;
  final bool canToggleMode;
  final _FilterEditorMode mode;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
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
          if (canToggleMode)
            SegmentedButton<_FilterEditorMode>(
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
              segments: const [
                ButtonSegment(
                  value: _FilterEditorMode.simple,
                  label: Text('Simple'),
                ),
                ButtonSegment(
                  value: _FilterEditorMode.advanced,
                  label: Text('Avanzado'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) {
                if (selection.first != mode) onToggleMode();
              },
            ),
          IconButton(
            tooltip: 'Limpiar',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: onReset,
          ),
          IconButton(icon: const Icon(Icons.close_rounded), onPressed: onClose),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _AdvancedOnlyMessage extends StatelessWidget {
  const _AdvancedOnlyMessage({
    required this.onEditAdvanced,
    required this.onReplaceSimple,
  });

  final VoidCallback onEditAdvanced;
  final VoidCallback onReplaceSimple;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Este filtro usa reglas avanzadas.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'La vista simple no puede editar OR, NOT o grupos anidados sin cambiar el significado del filtro.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: onEditAdvanced,
                  child: const Text('Editar avanzado'),
                ),
                TextButton(
                  onPressed: onReplaceSimple,
                  child: const Text('Crear filtro simple'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupEditor extends StatelessWidget {
  const _GroupEditor({
    required this.group,
    required this.options,
    required this.depth,
    required this.onChanged,
    this.onRemove,
  });

  static const int maxDepth = 2;

  final FilterGroup group;
  final _FilterOptions options;
  final int depth;
  final ValueChanged<FilterGroup> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: depth == 0 ? scheme.surface : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'and', label: Text('AND')),
                    ButtonSegment(value: 'or', label: Text('OR')),
                  ],
                  selected: {group.combinator == 'or' ? 'or' : 'and'},
                  onSelectionChanged: (selection) =>
                      onChanged(group.copyWith(combinator: selection.first)),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('NOT'),
                  selected: group.not,
                  onSelected: (value) => onChanged(group.copyWith(not: value)),
                ),
                const Spacer(),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Eliminar grupo',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (group.children.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: _EmptyHint('Agregá una condición para empezar.'),
              )
            else
              for (var i = 0; i < group.children.length; i++) ...[
                _buildChild(i),
                if (i != group.children.length - 1) const SizedBox(height: 8),
              ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _addChild(_defaultCondition('type')),
                  icon: const Icon(Icons.add),
                  label: const Text('Condición'),
                ),
                if (depth < maxDepth)
                  OutlinedButton.icon(
                    onPressed: () => _addChild(const FilterGroup()),
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('Grupo'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChild(int index) {
    final child = group.children[index];
    void replace(FilterNode node) {
      final next = [...group.children]..[index] = node;
      onChanged(group.copyWith(children: next));
    }

    void remove() {
      final next = [...group.children]..removeAt(index);
      onChanged(group.copyWith(children: next));
    }

    return switch (child) {
      FilterCondition() => _ConditionEditor(
        condition: child,
        options: options,
        onChanged: replace,
        onRemove: remove,
      ),
      FilterGroup() => _GroupEditor(
        group: child,
        options: options,
        depth: depth + 1,
        onChanged: replace,
        onRemove: remove,
      ),
    };
  }

  void _addChild(FilterNode child) {
    onChanged(group.copyWith(children: [...group.children, child]));
  }
}

class _ConditionEditor extends StatelessWidget {
  const _ConditionEditor({
    required this.condition,
    required this.options,
    required this.onChanged,
    required this.onRemove,
  });

  final FilterCondition condition;
  final _FilterOptions options;
  final ValueChanged<FilterNode> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final operators = _operatorsFor(condition.field);
    final operator = operators.contains(condition.operator)
        ? condition.operator
        : operators.first;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _fieldLabels.containsKey(condition.field)
                        ? condition.field
                        : 'type',
                    decoration: const InputDecoration(
                      labelText: 'Campo',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final entry in _fieldLabels.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (field) {
                      if (field == null) return;
                      onChanged(_defaultCondition(field));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: operator,
                    decoration: const InputDecoration(
                      labelText: 'Operador',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final op in operators)
                        DropdownMenuItem(
                          value: op,
                          child: Text(_operatorLabel(op)),
                        ),
                    ],
                    onChanged: (op) {
                      if (op == null) return;
                      onChanged(condition.copyWith(operator: op));
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Eliminar condición',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _valueEditor(context, condition.copyWith(operator: operator)),
          ],
        ),
      ),
    );
  }

  Widget _valueEditor(BuildContext context, FilterCondition current) {
    switch (current.field) {
      case 'type':
        return _enumChips(
          values: TxnType.values,
          selected: _asStringSet(current.value),
          onChanged: (ids) => onChanged(current.copyWith(value: ids.toList())),
        );
      case 'status':
        return _enumChips(
          values: TxnStatus.values,
          selected: _asStringSet(current.value),
          onChanged: (ids) => onChanged(current.copyWith(value: ids.toList())),
        );
      case 'account':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _entityChips(
              items: [for (final a in options.accounts) (a.id, a.name)],
              selected: _asStringSet(current.value),
              emptyText: 'No hay cuentas todavía.',
              onChanged: (ids) =>
                  onChanged(current.copyWith(value: ids.toList())),
            ),
            const SizedBox(height: 12),
            _SubLabel('Dirección'),
            const SizedBox(height: 4),
            SegmentedButton<AccountDirection>(
              showSelectedIcon: false,
              segments: [
                for (final dir in AccountDirection.values)
                  ButtonSegment(value: dir, label: Text(dir.label)),
              ],
              selected: {current.direction},
              onSelectionChanged: (selection) =>
                  onChanged(current.copyWith(direction: selection.first)),
            ),
          ],
        );
      case 'category':
        return _entityChips(
          items: [for (final c in options.categories) (c.id, c.name)],
          selected: _asStringSet(current.value),
          emptyText: 'No hay categorías todavía.',
          onChanged: (ids) => onChanged(current.copyWith(value: ids.toList())),
        );
      case 'tag':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _entityChips(
              items: [for (final t in options.tags) (t.id, t.name)],
              selected: _asStringSet(current.value),
              emptyText: 'No hay tags todavía.',
              onChanged: (ids) =>
                  onChanged(current.copyWith(value: ids.toList())),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _SubLabel('Coincidencia'),
                const SizedBox(width: 12),
                SegmentedButton<TagMatch>(
                  showSelectedIcon: false,
                  segments: [
                    for (final match in TagMatch.values)
                      ButtonSegment(value: match, label: Text(match.label)),
                  ],
                  selected: {current.match},
                  onSelectionChanged: (selection) =>
                      onChanged(current.copyWith(match: selection.first)),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Incluir subetiquetas'),
              value: current.includeSubtags,
              onChanged: (value) =>
                  onChanged(current.copyWith(includeSubtags: value)),
            ),
          ],
        );
      case 'currency':
        return _entityChips(
          items: [for (final c in options.currencies) (c, c)],
          selected: _asStringSet(current.value),
          emptyText: 'No hay monedas todavía.',
          single: true,
          onChanged: (ids) => onChanged(current.copyWith(value: ids.toList())),
        );
      case 'date':
        return _dateValueEditor(context, current);
      case 'amount':
        return _amountValueEditor(current);
      case 'text':
        return TextFormField(
          key: ValueKey('text-${current.value}'),
          initialValue: current.value is String ? current.value as String : '',
          decoration: const InputDecoration(
            hintText: 'Buscar nombre o descripción…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) => onChanged(current.copyWith(value: value)),
        );
      default:
        return const _EmptyHint('Campo no soportado.');
    }
  }

  Widget _dateValueEditor(BuildContext context, FilterCondition current) {
    if (current.operator == 'relative') {
      final selected = current.value is String ? current.value as String : null;
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final preset in DatePreset.values)
            ChoiceChip(
              label: Text(preset.label),
              selected: selected == preset.wire,
              onSelected: (_) =>
                  onChanged(current.copyWith(value: preset.wire)),
            ),
        ],
      );
    }
    final range = _rangeFromValue(current.value);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (range != null)
          InputChip(
            avatar: const Icon(Icons.event, size: 18),
            label: Text(_formatAdvancedRange(range)),
            onDeleted: () => onChanged(_defaultCondition('date')),
          ),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: const Text('Elegir rango'),
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(now.year - 10),
              lastDate: DateTime(now.year + 1, 12, 31),
              initialDateRange: range,
            );
            if (picked == null) return;
            onChanged(
              current.copyWith(
                value: {
                  'from': picked.start.toIso8601String(),
                  'to': picked.end.toIso8601String(),
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _amountValueEditor(FilterCondition current) {
    final values = _amountMap(current.value);
    final minText = _advancedCentsToText(values.min);
    final maxText = _advancedCentsToText(values.max);

    Widget field(String label, String initial, ValueChanged<int?> onChanged) {
      return TextFormField(
        key: ValueKey('$label-$initial-${current.operator}'),
        initialValue: initial,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (value) => onChanged(_advancedTextToCents(value)),
      );
    }

    if (current.operator == '>=') {
      return field('Mín', minText, (min) {
        onChanged(current.copyWith(value: {'min': min, 'max': null}));
      });
    }
    if (current.operator == '<=') {
      return field('Máx', maxText, (max) {
        onChanged(current.copyWith(value: {'min': null, 'max': max}));
      });
    }
    return Row(
      children: [
        Expanded(
          child: field('Mín', minText, (min) {
            onChanged(current.copyWith(value: {'min': min, 'max': values.max}));
          }),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: field('Máx', maxText, (max) {
            onChanged(current.copyWith(value: {'min': values.min, 'max': max}));
          }),
        ),
      ],
    );
  }

  Widget _enumChips<T extends WireLabeled>({
    required List<T> values,
    required Set<String> selected,
    required ValueChanged<Set<String>> onChanged,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final item in values)
          FilterChip(
            label: Text(item.label),
            selected: selected.contains(item.wire),
            onSelected: (_) => onChanged(_toggle(selected, item.wire)),
          ),
      ],
    );
  }

  Widget _entityChips({
    required List<(String, String)> items,
    required Set<String> selected,
    required String emptyText,
    required ValueChanged<Set<String>> onChanged,
    bool single = false,
  }) {
    if (items.isEmpty) return _EmptyHint(emptyText);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final item in items)
          FilterChip(
            label: Text(item.$2),
            selected: selected.contains(item.$1),
            onSelected: (value) {
              if (single) {
                onChanged(value ? {item.$1} : const {});
                return;
              }
              onChanged(_toggle(selected, item.$1));
            },
          ),
      ],
    );
  }
}

const _fieldLabels = <String, String>{
  'type': 'Tipo',
  'status': 'Estado',
  'date': 'Fecha',
  'account': 'Cuenta',
  'category': 'Categoría',
  'tag': 'Tag',
  'currency': 'Moneda',
  'amount': 'Monto',
  'text': 'Texto',
};

FilterCondition _defaultCondition(String field) {
  switch (field) {
    case 'type':
      return const FilterCondition(
        field: 'type',
        operator: 'in',
        value: ['expense'],
      );
    case 'status':
      return const FilterCondition(
        field: 'status',
        operator: 'in',
        value: ['cleared'],
      );
    case 'date':
      return const FilterCondition(
        field: 'date',
        operator: 'relative',
        value: 'this_month',
      );
    case 'account':
      return const FilterCondition(field: 'account', operator: 'in', value: []);
    case 'category':
      return const FilterCondition(
        field: 'category',
        operator: 'in',
        value: [],
      );
    case 'tag':
      return const FilterCondition(field: 'tag', operator: 'in', value: []);
    case 'currency':
      return const FilterCondition(
        field: 'currency',
        operator: 'in',
        value: [],
      );
    case 'amount':
      return const FilterCondition(
        field: 'amount',
        operator: 'between',
        value: {'min': null, 'max': null},
      );
    case 'text':
      return const FilterCondition(
        field: 'text',
        operator: 'contains',
        value: '',
      );
    default:
      return const FilterCondition(field: 'type', operator: 'in', value: []);
  }
}

List<String> _operatorsFor(String field) {
  switch (field) {
    case 'date':
      return const ['relative', 'between'];
    case 'amount':
      return const ['between', '>=', '<='];
    case 'text':
      return const ['contains', 'not contains'];
    case 'type':
    case 'status':
    case 'account':
    case 'category':
    case 'tag':
    case 'currency':
      return const ['in', 'not in'];
    default:
      return const ['in'];
  }
}

String _operatorLabel(String operator) {
  switch (operator) {
    case 'in':
      return 'incluye';
    case 'not in':
      return 'excluye';
    case 'relative':
      return 'relativa';
    case 'between':
      return 'entre';
    case '>=':
      return 'mayor o igual';
    case '<=':
      return 'menor o igual';
    case 'contains':
      return 'contiene';
    case 'not contains':
      return 'no contiene';
    default:
      return operator;
  }
}

Set<String> _asStringSet(Object? value) {
  return value is List ? value.whereType<String>().toSet() : const {};
}

Set<String> _toggle(Set<String> values, String value) {
  final next = {...values};
  if (!next.add(value)) next.remove(value);
  return next;
}

DateTimeRange? _rangeFromValue(Object? value) {
  if (value is! Map) return null;
  final from = value['from'];
  final to = value['to'];
  if (from is! String || to is! String) return null;
  final start = DateTime.tryParse(from);
  final end = DateTime.tryParse(to);
  if (start == null || end == null) return null;
  return DateTimeRange(start: start, end: end);
}

({int? min, int? max}) _amountMap(Object? value) {
  if (value is! Map) return (min: null, max: null);
  final min = value['min'];
  final max = value['max'];
  return (min: min is int ? min : null, max: max is int ? max : null);
}

String _advancedCentsToText(int? cents) {
  if (cents == null) return '';
  final value = cents / 100;
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

int? _advancedTextToCents(String raw) {
  final trimmed = raw.trim().replaceAll(',', '.');
  if (trimmed.isEmpty) return null;
  final parsed = double.tryParse(trimmed);
  if (parsed == null) return null;
  return (parsed * 100).round();
}

String _formatAdvancedRange(DateTimeRange range) {
  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return '${fmt(range.start)} → ${fmt(range.end)}';
}
