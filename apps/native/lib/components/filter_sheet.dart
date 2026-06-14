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
    });
  }

  void _apply() {
    final hasCurrency = _currency != null;
    final filter = TransactionFilter(
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
    Navigator.of(context).pop(filter);
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
        return Column(
          children: [
            _Header(
              onReset: _reset,
              onClose: () => Navigator.of(context).pop(),
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
}

class _Header extends StatelessWidget {
  const _Header({required this.onReset, required this.onClose});

  final VoidCallback onReset;
  final VoidCallback onClose;

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
          TextButton(onPressed: onReset, child: const Text('Limpiar')),
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
