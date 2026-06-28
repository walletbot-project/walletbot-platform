import 'dart:convert';

import 'package:app/components/dashboard/dashboard_background.dart';
import 'package:app/components/dashboard/dashboard_layout.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/components/filter_sheet.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

/// Opens the "add widget" flow as a modal sheet. Performs the create itself
/// (saved filter + widget row) and returns `true` when a widget was added.
///
/// [repos] is passed in explicitly because this sheet is pushed on a Navigator
/// that sits above the account-scoped providers (same reason as
/// `showFilterSheet`).
Future<bool> showAddWidgetSheet(BuildContext context, AppRepositories repos) =>
    _showWidgetSheet(context, repos);

/// Opens the same sheet pre-filled to edit an existing [widget]. [initialFilter]
/// is the widget's current saved filter resolved to a [TransactionFilter] (or
/// an empty filter when it has none). Returns `true` when changes were saved.
Future<bool> showEditWidgetSheet(
  BuildContext context,
  AppRepositories repos,
  DashboardWidget widget,
  TransactionFilter initialFilter,
) => _showWidgetSheet(
  context,
  repos,
  existing: widget,
  initialFilter: initialFilter,
);

Future<bool> _showWidgetSheet(
  BuildContext context,
  AppRepositories repos, {
  DashboardWidget? existing,
  TransactionFilter initialFilter = const TransactionFilter(),
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _WidgetSheet(
      repos: repos,
      existing: existing,
      initialFilter: initialFilter,
    ),
  );
  return saved ?? false;
}

const _aggregationLabels = {
  StatAggregation.sum: 'Suma',
  StatAggregation.net: 'Neto',
  StatAggregation.count: 'Conteo',
};

const _typeLabels = {
  WidgetType.stat: 'Valor',
  WidgetType.list: 'Lista',
  WidgetType.balance: 'Saldo',
  WidgetType.chart: 'Gráfico',
};

const _defaultWidthFor = {
  WidgetType.stat: DashboardWidth.third,
  WidgetType.list: DashboardWidth.full,
  WidgetType.balance: DashboardWidth.half,
  WidgetType.chart: DashboardWidth.full,
};

const _groupByLabels = {
  BreakdownGroupBy.category: 'Categoría',
  BreakdownGroupBy.account: 'Cuenta',
  BreakdownGroupBy.month: 'Mes',
};

const _chartKindLabels = {
  BreakdownChartKind.pie: 'Torta',
  BreakdownChartKind.bar: 'Barras',
  BreakdownChartKind.line: 'Línea',
};

class _WidgetSheet extends StatefulWidget {
  const _WidgetSheet({
    required this.repos,
    this.existing,
    this.initialFilter = const TransactionFilter(),
  });

  final AppRepositories repos;
  final DashboardWidget? existing;
  final TransactionFilter initialFilter;

  @override
  State<_WidgetSheet> createState() => _WidgetSheetState();
}

class _WidgetSheetState extends State<_WidgetSheet> {
  // Whether the background editor offers the "Valor" (range) mode. Disabled by
  // default; a widget already configured with it (e.g. by the agent) still
  // shows the option so it stays editable — see [_showValueBackgroundMode].
  static const bool _enableValueBackgroundMode = false;

  late WidgetType _type;
  late final TextEditingController _titleController;
  late final TextEditingController _limitController;
  late final TextEditingController _backgroundLowController;
  late final TextEditingController _backgroundHighController;
  late StatAggregation _aggregation;
  late BreakdownGroupBy _groupBy;
  late BreakdownChartKind _chartKind;
  late TransactionFilter _filter;
  late bool _advanced;
  late bool _simpleHasColor;
  late Color _fixedBackgroundColor;
  late Color _lowBackgroundColor;
  late Color _betweenBackgroundColor;
  late Color _highBackgroundColor;
  String? _currency;
  List<String> _currencies = const [];
  var _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final options = existing == null
        ? const <String, Object?>{}
        : _decodeOptions(existing.options);

    _type = existing == null
        ? WidgetType.stat
        : WidgetType.fromWire(existing.type) ?? WidgetType.stat;
    _titleController = TextEditingController(
      text: options['title'] as String? ?? '',
    );
    _limitController = TextEditingController(
      text: ((options['limit'] as num?)?.toInt() ?? 5).toString(),
    );
    _aggregation = _aggregationFromName(options['aggregation']);
    _groupBy =
        BreakdownGroupBy.fromWire(options['groupBy'] as String? ?? '') ??
        BreakdownGroupBy.category;
    _chartKind =
        BreakdownChartKind.fromWire(options['chartKind'] as String? ?? '') ??
        BreakdownChartKind.pie;
    _filter = widget.initialFilter;
    _currency = options['currency'] as String?;
    final background = DashboardBackgroundStyle.fromJson(options['background']);
    final valueBackground =
        background.value ?? DashboardValueBackground.defaults;
    _advanced = background.mode == DashboardBackgroundMode.value;
    _simpleHasColor = background.mode == DashboardBackgroundMode.fixed;
    _fixedBackgroundColor =
        background.fixedColor ?? dashboardBackgroundPalette.first;
    _lowBackgroundColor = valueBackground.lowColor;
    _betweenBackgroundColor = valueBackground.betweenColor;
    _highBackgroundColor = valueBackground.highColor;
    _backgroundLowController = TextEditingController(
      text: _formatNumber(valueBackground.low),
    );
    _backgroundHighController = TextEditingController(
      text: _formatNumber(valueBackground.high),
    );

    // Rebuild as the title is typed so the confirm button enables/disables.
    _titleController.addListener(_onFieldsChanged);
    _loadCurrencies();
  }

  void _onFieldsChanged() {
    if (mounted) setState(() {});
  }

  /// Whether the required fields are filled: a title always, plus a currency
  /// for the balance card. Drives the confirm button's enabled state.
  bool get _canSubmit {
    if (_titleController.text.trim().isEmpty) return false;
    if (_type == WidgetType.balance && _currency == null) return false;
    return true;
  }

  @override
  void dispose() {
    _titleController.removeListener(_onFieldsChanged);
    _titleController.dispose();
    _limitController.dispose();
    _backgroundLowController.dispose();
    _backgroundHighController.dispose();
    super.dispose();
  }

  static Map<String, Object?> _decodeOptions(String raw) {
    if (raw.isEmpty) return const {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded : const {};
  }

  static StatAggregation _aggregationFromName(Object? name) {
    for (final agg in StatAggregation.values) {
      if (agg.name == name) return agg;
    }
    return StatAggregation.sum;
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  static double _parseNumber(String raw, double fallback) =>
      double.tryParse(raw.trim().replaceAll(',', '.')) ?? fallback;

  Future<void> _loadCurrencies() async {
    final accounts = await widget.repos.accounts.listActive();
    final currencies = accounts.map((a) => a.currency).toSet().toList()..sort();
    if (!mounted) return;
    setState(() {
      _currencies = currencies;
      // Keep an already-set currency (editing a balance card); otherwise pick
      // the first available, falling back to ARS.
      _currency ??= currencies.isNotEmpty ? currencies.first : 'ARS';
    });
  }

  bool get _filterConfigured => !_filter.isEmpty;

  Future<void> _configureFilter() async {
    final result = await showFilterSheet(
      context,
      repos: widget.repos,
      initial: _filter,
      hiddenSections: const {FilterSection.status},
      // Keep the simple/advanced toggle available; hiding a section otherwise
      // suppresses it (the sheet defaults `allowAdvanced` to "no hidden
      // sections").
      allowAdvanced: true,
    );
    if (result != null) setState(() => _filter = result);
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Ingresá un título')),
      );
      return;
    }
    if (_type == WidgetType.balance && _currency == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Seleccioná una moneda')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final options = <String, Object?>{
        ...switch (_type) {
          WidgetType.stat => {'title': title, 'aggregation': _aggregation.name},
          WidgetType.list => {
            'title': title,
            'limit': int.tryParse(_limitController.text.trim()) ?? 5,
          },
          WidgetType.balance => {'title': title, 'currency': _currency},
          WidgetType.chart => {
            'title': title,
            'groupBy': _groupBy.wire,
            'chartKind': _chartKind.wire,
          },
        },
      };
      final background = _backgroundFromFields().toJson();
      if (background != null) options['background'] = background;

      final existing = widget.existing;
      if (existing == null) {
        await _create(title, options);
      } else {
        await _update(existing, title, options);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo guardar el widget: $error')),
      );
    }
  }

  DashboardBackgroundStyle _backgroundFromFields() {
    final defaults = DashboardValueBackground.defaults;
    final mode = _advanced
        ? DashboardBackgroundMode.value
        : (_simpleHasColor
              ? DashboardBackgroundMode.fixed
              : DashboardBackgroundMode.none);
    return DashboardBackgroundStyle(
      mode: mode,
      fixedColor: _fixedBackgroundColor,
      value: DashboardValueBackground(
        low: _parseNumber(_backgroundLowController.text, defaults.low),
        high: _parseNumber(_backgroundHighController.text, defaults.high),
        lowColor: _lowBackgroundColor,
        betweenColor: _betweenBackgroundColor,
        highColor: _highBackgroundColor,
      ),
    );
  }

  Future<void> _create(String title, Map<String, Object?> options) async {
    final existing = await widget.repos.dashboard.listActive();
    // Drop the new widget on a fresh row below everything else.
    final layout = DashboardGridLayout.fromPlacements(
      resolvePlacements([
        for (final row in existing)
          PlacementInput(
            id: row.id,
            width: DashboardWidth.fromWire(row.width) ?? DashboardWidth.full,
            coord: dashboardLayoutFromOptions(row.options),
          ),
      ]),
    );
    final placedOptions = {
      ...options,
      'layout': {'row': layout.rowCount, 'col': 0},
    };
    String? filterId;
    if (_type != WidgetType.balance && _filterConfigured) {
      filterId = await widget.repos.savedFilters.create(
        name: title,
        config: jsonEncode(_filter.toCanonicalJson()),
      );
    }
    await widget.repos.dashboard.create(
      type: _type.wire,
      filterId: filterId,
      position: existing.length,
      width: _defaultWidthFor[_type]!.wire,
      options: encodeWidgetOptions(placedOptions),
    );
  }

  Future<void> _update(
    DashboardWidget existing,
    String title,
    Map<String, Object?> options,
  ) async {
    // Resolve the filter: balance cards carry none; otherwise update the
    // existing saved filter in place or create one, and clear it when the
    // filter was emptied. Width and position are owned by the tile controls,
    // so they're left untouched here.
    String? filterId;
    if (_type != WidgetType.balance && _filterConfigured) {
      final config = jsonEncode(_filter.toCanonicalJson());
      if (existing.filterId != null) {
        await widget.repos.savedFilters.update(
          existing.filterId!,
          name: Value(title),
          config: Value(config),
        );
        filterId = existing.filterId;
      } else {
        filterId = await widget.repos.savedFilters.create(
          name: title,
          config: config,
        );
      }
    }
    await widget.repos.dashboard.update(
      existing.id,
      type: Value(_type.wire),
      filterId: Value(filterId),
      options: Value(encodeWidgetOptions(options)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `viewInsets.bottom` keeps the sheet above the keyboard; `SafeArea`
    // (bottom only) keeps the action buttons clear of the Android system
    // navigation bar / iOS home indicator.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isEditing ? 'Editar widget' : 'Agregar widget',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),

              Text('Tipo', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final type in WidgetType.values)
                    ChoiceChip(
                      label: Text(_typeLabels[type]!),
                      selected: _type == type,
                      onSelected: (_) => setState(() => _type = type),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              ..._typeSpecificFields(theme),

              _backgroundFields(theme),

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_saving || !_canSubmit) ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isEditing ? 'Guardar' : 'Agregar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether the "Avanzado" (value-range) toggle is offered. Gated off by
  /// [_enableValueBackgroundMode], but always shown when the widget is already
  /// on that mode (e.g. configured by the agent) so it stays editable.
  bool get _showAdvancedToggle => _enableValueBackgroundMode || _advanced;

  Widget _backgroundFields(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Fondo', style: theme.textTheme.titleSmall),
            if (_showAdvancedToggle) ...[
              const Spacer(),
              Text(
                'Avanzado',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Switch(
                value: _advanced,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => setState(() => _advanced = v),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Simple mode: pick a fixed color, or the leading "sin color" swatch to
        // leave the widget on its base background.
        if (!_advanced)
          _ColorSwatches(
            selected: _fixedBackgroundColor,
            cleared: !_simpleHasColor,
            onCleared: () => setState(() => _simpleHasColor = false),
            onSelected: (color) => setState(() {
              _simpleHasColor = true;
              _fixedBackgroundColor = color;
            }),
          ),
        if (_advanced) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _backgroundLowController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Bajo',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _backgroundHighController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Alto',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ValueColorRow(
            label: 'Menor que bajo',
            selected: _lowBackgroundColor,
            onSelected: (color) => setState(() {
              _lowBackgroundColor = color;
            }),
          ),
          const SizedBox(height: 10),
          _ValueColorRow(
            label: 'Entre bajo y alto',
            selected: _betweenBackgroundColor,
            onSelected: (color) => setState(() {
              _betweenBackgroundColor = color;
            }),
          ),
          const SizedBox(height: 10),
          _ValueColorRow(
            label: 'Mayor que alto',
            selected: _highBackgroundColor,
            onSelected: (color) => setState(() {
              _highBackgroundColor = color;
            }),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  List<Widget> _typeSpecificFields(ThemeData theme) {
    switch (_type) {
      case WidgetType.stat:
        return [
          Text('Agregación', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final agg in StatAggregation.values)
                ChoiceChip(
                  label: Text(_aggregationLabels[agg]!),
                  selected: _aggregation == agg,
                  onSelected: (_) => setState(() => _aggregation = agg),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _filterButton(),
        ];
      case WidgetType.list:
        return [
          TextField(
            controller: _limitController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cantidad de movimientos',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          _filterButton(),
        ];
      case WidgetType.chart:
        return [
          Text('Agrupar por', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final groupBy in BreakdownGroupBy.values)
                ChoiceChip(
                  label: Text(_groupByLabels[groupBy]!),
                  selected: _groupBy == groupBy,
                  onSelected: (_) => setState(() => _groupBy = groupBy),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Tipo de gráfico', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final kind in BreakdownChartKind.values)
                ChoiceChip(
                  label: Text(_chartKindLabels[kind]!),
                  selected: _chartKind == kind,
                  onSelected: (_) => setState(() => _chartKind = kind),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _filterButton(),
        ];
      case WidgetType.balance:
        return [
          Text('Moneda', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_currencies.isEmpty)
            Text(
              'No hay cuentas todavía; se usará ARS.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              children: [
                for (final currency in _currencies)
                  ChoiceChip(
                    label: Text(currency),
                    selected: _currency == currency,
                    onSelected: (_) => setState(() => _currency = currency),
                  ),
              ],
            ),
          const SizedBox(height: 16),
        ];
    }
  }

  Widget _filterButton() {
    return _FilterCallToAction(
      configured: _filterConfigured,
      onConfigure: _configureFilter,
      onClear: () => setState(() => _filter = const TransactionFilter()),
    );
  }
}

class _ValueColorRow extends StatelessWidget {
  const _ValueColorRow({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        _ColorSwatches(selected: selected, onSelected: onSelected),
      ],
    );
  }
}

class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches({
    required this.selected,
    required this.onSelected,
    this.cleared = false,
    this.onCleared,
  });

  final Color selected;
  final ValueChanged<Color> onSelected;

  /// Whether the "sin color" (no background) option is the active selection.
  /// Only meaningful when [onCleared] is provided.
  final bool cleared;

  /// When provided, a leading "sin color" swatch is shown that clears the
  /// background; tapping it invokes this.
  final VoidCallback? onCleared;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final onCleared = this.onCleared;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (onCleared != null)
          Tooltip(
            message: 'Sin color',
            child: InkResponse(
              radius: 20,
              onTap: onCleared,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cleared ? colors.primary : colors.outlineVariant,
                    width: cleared ? 2.4 : 1,
                  ),
                ),
                child: Icon(
                  Icons.format_color_reset_rounded,
                  size: 16,
                  color: cleared ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        for (final color in dashboardBackgroundPalette)
          Tooltip(
            message: 'Color',
            child: InkResponse(
              radius: 20,
              onTap: () => onSelected(color),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (!cleared && color == selected)
                        ? colors.primary
                        : colors.outlineVariant,
                    width: (!cleared && color == selected) ? 2.4 : 1,
                  ),
                ),
                child: (!cleared && color == selected)
                    ? Icon(Icons.check_rounded, size: 16, color: colors.primary)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// The filter call-to-action. When no filter is set it's a full-width filled
/// button that gently pulses to invite a tap; once configured it settles into a
/// calm outlined "Editar filtro" action alongside a clear (✕) action. The pulse
/// is skipped when the OS "reduce motion" setting is on.
class _FilterCallToAction extends StatefulWidget {
  const _FilterCallToAction({
    required this.configured,
    required this.onConfigure,
    required this.onClear,
  });

  final bool configured;
  final VoidCallback onConfigure;
  final VoidCallback onClear;

  @override
  State<_FilterCallToAction> createState() => _FilterCallToActionState();
}

class _FilterCallToActionState extends State<_FilterCallToAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.configured) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: widget.onConfigure,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Editar filtro'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Quitar filtro',
            icon: const Icon(Icons.close),
            onPressed: widget.onClear,
          ),
        ],
      );
    }

    final button = SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: widget.onConfigure,
        icon: const Icon(Icons.tune, size: 18),
        label: const Text('Configurar filtro'),
      ),
    );

    // Respect reduced-motion: show the prominent button without the pulse.
    if (MediaQuery.of(context).disableAnimations) return button;

    return AnimatedBuilder(
      animation: _controller,
      child: button,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Transform.scale(scale: 1 + 0.03 * t, child: child);
      },
    );
  }
}
