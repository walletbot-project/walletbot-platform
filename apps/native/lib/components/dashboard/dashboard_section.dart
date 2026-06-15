import 'package:app/components/dashboard/add_widget_sheet.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/components/dashboard/dashboard_view.dart';
import 'package:app/data/data.dart';
import 'package:app/data/queries/stream_utils.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Reactive source for the home dashboard: joins the persisted widget rows with
/// the saved filters they reference and resolves each into a renderable spec,
/// then hands the ordered list to [DashboardView]. Re-emits on any local write
/// or sync merge to either table.
class DashboardSection extends StatefulWidget {
  const DashboardSection({
    super.key,
    this.editing = false,
    this.onStartEditing,
    this.onOpenFilter,
  });

  final bool editing;
  final VoidCallback? onStartEditing;
  final ValueChanged<TransactionFilter>? onOpenFilter;

  @override
  State<DashboardSection> createState() => _DashboardSectionState();
}

class _DashboardSectionState extends State<DashboardSection> {
  var _ordered = <DashboardWidget>[];
  final _pendingDeletes = <String>{};
  final _pendingWidths = <String, DashboardWidth>{};
  String? _selectedId;

  @override
  void didUpdateWidget(DashboardSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editing && !widget.editing) {
      _selectedId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repos = context.read<AppRepositories>();
    final stream = combineLatest2(
      repos.dashboard.watchWidgets(),
      repos.savedFilters.watchActive(),
      (List<DashboardWidget> widgets, List<SavedFilter> filters) =>
          (widgets, filters),
    );

    return StreamBuilder<(List<DashboardWidget>, List<SavedFilter>)>(
      stream: stream,
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        if (snapshot.hasError) {
          return Text(
            'No se pudo cargar el tablero.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final (widgets, filters) = snapshot.data!;
        _syncOrdered(widgets);
        if (widgets.isEmpty) {
          return Text(
            'Tu tablero está vacío. Agregá un widget para empezar.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }

        final filtersById = {for (final f in filters) f.id: f};
        final visibleWidgets = widget.editing ? _ordered : widgets;
        final items = visibleWidgets
            .map((w) {
              final spec = dashboardSpecFromRow(w, filtersById);
              if (spec == null) return null;
              return DashboardViewItem(row: w, spec: spec);
            })
            .whereType<DashboardViewItem>()
            .toList();
        if (_selectedId != null &&
            !items.any((item) => item.row.id == _selectedId)) {
          _selectedId = null;
        }
        return DashboardView(
          items: items,
          editing: widget.editing,
          selectedItemId: _selectedId,
          onTapItem: widget.editing
              ? _selectItem
              : widget.onOpenFilter == null
              ? null
              : (item) => widget.onOpenFilter!(_activityFilterFor(item.spec)),
          onLongPressItem: widget.editing
              ? null
              : (item) {
                  setState(() => _selectedId = item.row.id);
                  widget.onStartEditing?.call();
                },
          onMoveItem: widget.editing ? _moveItem : null,
          onWidthChanged: widget.editing ? _changeWidth : null,
          onEditItem: widget.editing
              ? (item) => _editItem(repos, item, filtersById)
              : null,
          onDeleteItem: widget.editing ? _deleteItem : null,
        );
      },
    );
  }

  void _syncOrdered(List<DashboardWidget> incomingWidgets) {
    final incomingIds = {for (final row in incomingWidgets) row.id};
    _pendingDeletes.removeWhere((id) => !incomingIds.contains(id));

    final widgets = [
      for (final row in incomingWidgets)
        if (!_pendingDeletes.contains(row.id)) _withPendingWidth(row),
    ];

    if (!widget.editing) {
      _ordered = [...widgets];
      return;
    }

    final incomingById = {for (final w in widgets) w.id: w};
    final next = <DashboardWidget>[];
    final used = <String>{};
    for (final row in _ordered) {
      final fresh = incomingById[row.id];
      if (fresh == null) continue;
      next.add(fresh);
      used.add(row.id);
    }
    for (final row in widgets) {
      if (!used.contains(row.id)) next.add(row);
    }
    _ordered = next;
  }

  DashboardWidget _withPendingWidth(DashboardWidget row) {
    final pendingWidth = _pendingWidths[row.id];
    if (pendingWidth == null) return row;
    if (row.width == pendingWidth.wire) {
      _pendingWidths.remove(row.id);
      return row;
    }
    return row.copyWith(width: pendingWidth.wire);
  }

  void _selectItem(DashboardViewItem item) {
    setState(() => _selectedId = item.row.id);
  }

  Future<void> _moveItem(String draggedId, String targetId) async {
    if (draggedId == targetId) return;
    final oldIndex = _ordered.indexWhere((row) => row.id == draggedId);
    final targetIndex = _ordered.indexWhere((row) => row.id == targetId);
    if (oldIndex == -1 || targetIndex == -1) return;

    final previous = [..._ordered];
    setState(() {
      final row = _ordered.removeAt(oldIndex);
      _ordered.insert(targetIndex, row);
      _selectedId = draggedId;
    });

    try {
      await context.read<AppRepositories>().dashboard.reorder(
        _ordered.map((row) => row.id).toList(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _ordered = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo reordenar el tablero: $error')),
      );
    }
  }

  Future<void> _changeWidth(
    DashboardViewItem item,
    DashboardWidth width,
  ) async {
    if (item.spec.width == width) return;
    final previous = [..._ordered];
    setState(() {
      _pendingWidths[item.row.id] = width;
      _ordered = [
        for (final row in _ordered)
          row.id == item.row.id ? row.copyWith(width: width.wire) : row,
      ];
      _selectedId = item.row.id;
    });

    try {
      await context.read<AppRepositories>().dashboard.update(
        item.row.id,
        width: Value(width.wire),
      );
    } catch (error) {
      if (!mounted) return;
      _pendingWidths.remove(item.row.id);
      setState(() => _ordered = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cambiar el tamaño: $error')),
      );
    }
  }

  Future<void> _editItem(
    AppRepositories repos,
    DashboardViewItem item,
    Map<String, SavedFilter> filtersById,
  ) {
    return showEditWidgetSheet(
      context,
      repos,
      item.row,
      dashboardFilterFromRow(item.row, filtersById),
    );
  }

  Future<void> _deleteItem(DashboardViewItem item) async {
    final dashboard = context.read<AppRepositories>().dashboard;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar widget'),
        content: Text('¿Quitar "${_titleOf(item.row)}" del tablero?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final previous = [..._ordered];
    setState(() {
      _pendingDeletes.add(item.row.id);
      _ordered = _ordered.where((row) => row.id != item.row.id).toList();
      if (_selectedId == item.row.id) _selectedId = null;
    });

    try {
      await dashboard.archive(item.row.id);
    } catch (error) {
      if (!mounted) return;
      _pendingDeletes.remove(item.row.id);
      setState(() => _ordered = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo quitar el widget: $error')),
      );
    }
  }

  TransactionFilter _activityFilterFor(DashboardWidgetSpec spec) {
    return switch (spec) {
      StatWidgetSpec(:final filter) => filter,
      TransactionListWidgetSpec(:final filter) => filter,
      ChartWidgetSpec(:final filter) => filter,
      BalanceCardWidgetSpec(:final currency) => TransactionFilter(
        currency: currency.isEmpty ? null : currency,
      ),
    };
  }

  String _titleOf(DashboardWidget row) {
    final spec = dashboardSpecFromRow(row, const {});
    return switch (spec) {
      StatWidgetSpec(:final title) ||
      TransactionListWidgetSpec(:final title) ||
      BalanceCardWidgetSpec(:final title) ||
      ChartWidgetSpec(
        :final title,
      ) => title.isEmpty ? _typeLabelOf(row) : title,
      null => _typeLabelOf(row),
    };
  }

  String _typeLabelOf(DashboardWidget row) {
    return switch (WidgetType.fromWire(row.type)) {
      WidgetType.stat => 'Valor',
      WidgetType.list => 'Lista',
      WidgetType.balance => 'Saldo',
      WidgetType.chart => 'Gráfico',
      null => 'Widget',
    };
  }
}
