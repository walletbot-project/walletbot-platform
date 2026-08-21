import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/adaptive_modal.dart';
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

/// Opens the filter editor: a draggable bottom sheet on compact windows, a
/// centered dialog on medium/expanded ones (it re-frames live if the window is
/// resized across the breakpoint). Resolves to the edited [TransactionFilter]
/// when the user taps "Aplicar", or `null` if dismissed.
///
/// Pass [hiddenSections] to suppress dimensions the caller edits elsewhere
/// (e.g. the activity bar owns type + text). Hidden sections keep their
/// incoming values on both apply and "Limpiar".
Future<TransactionFilter?> showFilterSheet(
  BuildContext context, {
  TransactionFilter initial = const TransactionFilter(),
  Set<FilterSection> hiddenSections = const {},
  bool? allowAdvanced,
  AppRepositories? repos,
}) {
  // Read the repositories from the *calling* context: the modal route is
  // pushed by a Navigator that sits above the account-scoped providers, so
  // the sheet's own context can't reach them. Callers already inside such a
  // modal (e.g. the add-widget sheet) pass [repos] in directly.
  final resolvedRepos = repos ?? context.read<AppRepositories>();
  return showAdaptiveModal<TransactionFilter>(
    context,
    isScrollControlled: true,
    builder: (_) => FilterSheet(
      repos: resolvedRepos,
      initial: initial,
      hiddenSections: hiddenSections,
      allowAdvanced: allowAdvanced,
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
    this.allowAdvanced,
  });

  final AppRepositories repos;
  final TransactionFilter initial;
  final Set<FilterSection> hiddenSections;

  /// Whether the advanced editor toggle is offered. Defaults to "only when no
  /// sections are hidden", since the advanced tree ignores [hiddenSections] and
  /// can edit dimensions the caller owns elsewhere. Pass `true` to force it on.
  final bool? allowAdvanced;

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

  bool get _canUseAdvanced =>
      widget.allowAdvanced ?? widget.hiddenSections.isEmpty;

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

  /// Toggles a tag selection. Deselecting a tag also drops every descendant
  /// from the selection so a hidden subtag (whose parent is no longer selected)
  /// can't linger in the filter.
  void _toggleTag(String id, bool selected, List<Tag> tags) {
    setState(() {
      if (selected) {
        _tagIds.add(id);
        return;
      }
      final childrenByParent = <String, List<String>>{};
      for (final tag in tags) {
        final parentId = tag.parentId;
        if (parentId != null) {
          childrenByParent.putIfAbsent(parentId, () => []).add(tag.id);
        }
      }
      final queue = <String>[id];
      while (queue.isNotEmpty) {
        final next = queue.removeAt(0);
        _tagIds.remove(next);
        queue.addAll(childrenByParent[next] ?? const <String>[]);
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
    // All editing state lives in this State object, *above* the branch below,
    // so it survives when the enclosing AdaptiveSurfaceRoute morphs between
    // presentations on window resize.
    final style =
        AdaptiveModalScope.maybeOf(context) ?? AdaptiveModalStyle.bottomSheet;
    if (style == AdaptiveModalStyle.dialog) {
      // Dialog: the route already caps the height, so the body just fills it —
      // no drag-to-size affordance.
      return _buildSheetBody(context, null);
    }
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: _buildSheetBody,
    );
  }

  Widget _buildSheetBody(
    BuildContext context,
    ScrollController? scrollController,
  ) {
    return Padding(
      // Lift the whole sheet above the software keyboard so the action bar
      // and the lower form fields don't get hidden behind it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                        context.l10n.filterOptionsLoadFailed(snapshot.error!),
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
                      child: Text(context.l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
                      child: Text(context.l10n.apply),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    ScrollController? scrollController,
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
            title: context.l10n.type,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final type in TxnType.values)
                  FilterChip(
                    label: Text(context.l10n.txnType(type)),
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
        if (_shows(FilterSection.date))
          _Section(
            title: context.l10n.date,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final preset in DatePreset.values)
                  ChoiceChip(
                    label: Text(context.l10n.datePreset(preset)),
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
                    label: Text(context.l10n.customRange),
                    onPressed: _pickDateRange,
                  ),
              ],
            ),
          ),
        if (_shows(FilterSection.accounts))
          _Section(
            title: context.l10n.accounts,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (options.accounts.isEmpty)
                  _EmptyHint(context.l10n.noAccountsYet)
                else
                  _ExpandableChips(
                    chips: [
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
                  _SubLabel(context.l10n.transferDirection),
                  const SizedBox(height: 4),
                  SegmentedButton<AccountDirection>(
                    showSelectedIcon: false,
                    segments: [
                      for (final dir in AccountDirection.values)
                        ButtonSegment(
                          value: dir,
                          label: Text(context.l10n.accountDirection(dir)),
                        ),
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
            title: context.l10n.categories,
            child: options.categories.isEmpty
                ? _EmptyHint(context.l10n.noCategoriesYet)
                : _ExpandableChips(
                    chips: [
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
        if (_shows(FilterSection.tags)) ..._buildTagSections(options),
        if (_shows(FilterSection.status))
          _Section(
            title: context.l10n.status,
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(context.l10n.any),
                  selected: _status == null,
                  onSelected: (_) => setState(() => _status = null),
                ),
                for (final status in TxnStatus.values)
                  ChoiceChip(
                    label: Text(context.l10n.txnStatus(status)),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
              ],
            ),
          ),
        if (_shows(FilterSection.currency))
          _Section(
            title: context.l10n.currency,
            child: options.currencies.isEmpty
                ? _EmptyHint(context.l10n.noCurrenciesYet)
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
            title: context.l10n.amount,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasCurrency)
                  _EmptyHint(context.l10n.selectCurrencyForAmount)
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
                            labelText: context.l10n.minimum,
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
                            labelText: context.l10n.maximum,
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
            title: context.l10n.text,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
      ],
    );
  }

  /// Tags split into a top-level section plus a contextual "Subetiquetas"
  /// section that only lists the children of the currently selected tags.
  List<Widget> _buildTagSections(_FilterOptions options) {
    final topLevel = [
      for (final tag in options.tags)
        if (tag.parentId == null) tag,
    ];
    final subtags = [
      for (final tag in options.tags)
        if (tag.parentId != null && _tagIds.contains(tag.parentId)) tag,
    ];

    Widget chip(Tag tag) => FilterChip(
      label: Text(tag.name),
      selected: _tagIds.contains(tag.id),
      onSelected: (selected) => _toggleTag(tag.id, selected, options.tags),
    );

    return [
      _Section(
        title: context.l10n.tags,
        child: topLevel.isEmpty
            ? _EmptyHint(context.l10n.noTagsYet)
            : _ExpandableChips(chips: [for (final tag in topLevel) chip(tag)]),
      ),
      if (subtags.isNotEmpty)
        _Section(
          title: context.l10n.subtags,
          child: _ExpandableChips(
            chips: [for (final tag in subtags) chip(tag)],
          ),
        ),
    ];
  }

  String _formatRange(DateTimeRange range) =>
      formatDateRange(range.start, range.end, context.localeName);

  Widget _buildAdvancedForm(
    ScrollController? scrollController,
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
              context.l10n.filters,
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
              segments: [
                ButtonSegment(
                  value: _FilterEditorMode.simple,
                  label: Text(context.l10n.simple),
                ),
                ButtonSegment(
                  value: _FilterEditorMode.advanced,
                  label: Text(context.l10n.advanced),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) {
                if (selection.first != mode) onToggleMode();
              },
            ),
          IconButton(
            tooltip: context.l10n.clear,
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: onReset,
          ),
          IconButton(icon: const Icon(Icons.close_rounded), onPressed: onClose),
        ],
      ),
    );
  }
}

/// Above this many chips, a selectable section collapses behind a "Ver más"
/// button so long account/tag/category lists don't dominate the sheet.
const int _chipCollapseThreshold = 12;

/// A [Wrap] of [chips] that collapses to [threshold] items behind a "Ver más"
/// toggle when the list is longer. Keeps its own expand/collapse state.
class _ExpandableChips extends StatefulWidget {
  const _ExpandableChips({required this.chips});

  final List<Widget> chips;

  @override
  State<_ExpandableChips> createState() => _ExpandableChipsState();
}

class _ExpandableChipsState extends State<_ExpandableChips> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final chips = widget.chips;
    final collapses = chips.length > _chipCollapseThreshold;
    final visible = collapses && !_expanded
        ? chips.sublist(0, _chipCollapseThreshold)
        : chips;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 4, children: visible),
        if (collapses)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded
                    ? context.l10n.showLess
                    : context.l10n.showMore(
                        chips.length - _chipCollapseThreshold,
                      ),
              ),
            ),
          ),
      ],
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
              context.l10n.advancedFilterNotice,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.advancedFilterWarning,
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
                  child: Text(context.l10n.editAdvanced),
                ),
                TextButton(
                  onPressed: onReplaceSimple,
                  child: Text(context.l10n.createSimpleFilter),
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
                  segments: [
                    ButtonSegment(
                      value: 'and',
                      label: Text(context.l10n.filterAnd),
                    ),
                    ButtonSegment(
                      value: 'or',
                      label: Text(context.l10n.filterOr),
                    ),
                  ],
                  selected: {group.combinator == 'or' ? 'or' : 'and'},
                  onSelectionChanged: (selection) =>
                      onChanged(group.copyWith(combinator: selection.first)),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(context.l10n.filterNot),
                  selected: group.not,
                  onSelected: (value) => onChanged(group.copyWith(not: value)),
                ),
                const Spacer(),
                if (onRemove != null)
                  IconButton(
                    tooltip: context.l10n.deleteGroup,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (group.children.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _EmptyHint(context.l10n.addConditionToStart),
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
                  label: Text(context.l10n.condition),
                ),
                if (depth < maxDepth)
                  OutlinedButton.icon(
                    onPressed: () => _addChild(const FilterGroup()),
                    icon: const Icon(Icons.account_tree_outlined),
                    label: Text(context.l10n.group),
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
    final fieldLabels = _fieldLabels(context.l10n);
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
                    initialValue: fieldLabels.containsKey(condition.field)
                        ? condition.field
                        : 'type',
                    decoration: InputDecoration(
                      labelText: context.l10n.field,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final entry in fieldLabels.entries)
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
                    decoration: InputDecoration(
                      labelText: context.l10n.operator,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final op in operators)
                        DropdownMenuItem(
                          value: op,
                          child: Text(_operatorLabel(context.l10n, op)),
                        ),
                    ],
                    onChanged: (op) {
                      if (op == null) return;
                      onChanged(condition.copyWith(operator: op));
                    },
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.deleteCondition,
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
          labelFor: context.l10n.txnType,
          selected: _asStringSet(current.value),
          onChanged: (ids) => onChanged(current.copyWith(value: ids.toList())),
        );
      case 'status':
        return _enumChips(
          values: TxnStatus.values,
          labelFor: context.l10n.txnStatus,
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
              emptyText: context.l10n.noAccountsYet,
              onChanged: (ids) =>
                  onChanged(current.copyWith(value: ids.toList())),
            ),
            const SizedBox(height: 12),
            _SubLabel(context.l10n.direction),
            const SizedBox(height: 4),
            SegmentedButton<AccountDirection>(
              showSelectedIcon: false,
              segments: [
                for (final dir in AccountDirection.values)
                  ButtonSegment(
                    value: dir,
                    label: Text(context.l10n.accountDirection(dir)),
                  ),
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
          emptyText: context.l10n.noCategoriesYet,
          onChanged: (ids) => onChanged(current.copyWith(value: ids.toList())),
        );
      case 'tag':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _entityChips(
              items: [for (final t in options.tags) (t.id, t.name)],
              selected: _asStringSet(current.value),
              emptyText: context.l10n.noTagsYet,
              onChanged: (ids) =>
                  onChanged(current.copyWith(value: ids.toList())),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _SubLabel(context.l10n.match),
                const SizedBox(width: 12),
                SegmentedButton<TagMatch>(
                  showSelectedIcon: false,
                  segments: [
                    for (final match in TagMatch.values)
                      ButtonSegment(
                        value: match,
                        label: Text(context.l10n.tagMatch(match)),
                      ),
                  ],
                  selected: {current.match},
                  onSelectionChanged: (selection) =>
                      onChanged(current.copyWith(match: selection.first)),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.includeSubtags),
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
          emptyText: context.l10n.noCurrenciesYet,
          single: true,
          onChanged: (ids) => onChanged(current.copyWith(value: ids.toList())),
        );
      case 'date':
        return _dateValueEditor(context, current);
      case 'amount':
        return _amountValueEditor(context, current);
      case 'text':
        return TextFormField(
          key: ValueKey('text-${current.value}'),
          initialValue: current.value is String ? current.value as String : '',
          decoration: InputDecoration(
            hintText: context.l10n.searchHint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) => onChanged(current.copyWith(value: value)),
        );
      default:
        return _EmptyHint(context.l10n.unsupportedField);
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
              label: Text(context.l10n.datePreset(preset)),
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
            label: Text(
              formatDateRange(range.start, range.end, context.localeName),
            ),
            onDeleted: () => onChanged(_defaultCondition('date')),
          ),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(context.l10n.chooseRange),
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

  Widget _amountValueEditor(BuildContext context, FilterCondition current) {
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
      return field(context.l10n.minimum, minText, (min) {
        onChanged(current.copyWith(value: {'min': min, 'max': null}));
      });
    }
    if (current.operator == '<=') {
      return field(context.l10n.maximum, maxText, (max) {
        onChanged(current.copyWith(value: {'min': null, 'max': max}));
      });
    }
    return Row(
      children: [
        Expanded(
          child: field(context.l10n.minimum, minText, (min) {
            onChanged(current.copyWith(value: {'min': min, 'max': values.max}));
          }),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: field(context.l10n.maximum, maxText, (max) {
            onChanged(current.copyWith(value: {'min': values.min, 'max': max}));
          }),
        ),
      ],
    );
  }

  Widget _enumChips<T extends WireValue>({
    required List<T> values,
    required String Function(T) labelFor,
    required Set<String> selected,
    required ValueChanged<Set<String>> onChanged,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final item in values)
          FilterChip(
            label: Text(labelFor(item)),
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

Map<String, String> _fieldLabels(AppLocalizations l10n) => {
  'type': l10n.type,
  'status': l10n.status,
  'date': l10n.date,
  'account': l10n.account,
  'category': l10n.category,
  'tag': l10n.tags,
  'currency': l10n.currency,
  'amount': l10n.amount,
  'text': l10n.text,
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

String _operatorLabel(AppLocalizations l10n, String operator) {
  switch (operator) {
    case 'in':
      return l10n.operatorIncludes;
    case 'not in':
      return l10n.operatorExcludes;
    case 'relative':
      return l10n.operatorRelative;
    case 'between':
      return l10n.operatorBetween;
    case '>=':
      return l10n.operatorGreaterEqual;
    case '<=':
      return l10n.operatorLessEqual;
    case 'contains':
      return l10n.operatorContains;
    case 'not contains':
      return l10n.operatorNotContains;
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
