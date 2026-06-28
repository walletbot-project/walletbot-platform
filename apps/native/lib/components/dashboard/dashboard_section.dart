import 'package:app/components/dashboard/add_widget_sheet.dart';
import 'package:app/components/dashboard/dashboard_layout.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/components/dashboard/dashboard_view.dart';
import 'package:app/data/data.dart';
import 'package:app/data/queries/stream_utils.dart';
import 'package:app/database.dart';
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
  // Optimistic layout writes awaiting their stream round-trip, keyed by widget
  // id. Each holds the exact `options` (carrying the new `{row, col}`) and
  // `width` we wrote, so a stream re-emit doesn't flicker back to stale content
  // before the write lands. Cleared once the incoming row matches.
  final _pendingLayout = <String, ({String options, String width})>{};
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
          onPlaceInCell: widget.editing ? _placeInCell : null,
          onSwap: widget.editing ? _swap : null,
          onInsertRow: widget.editing ? _insertRow : null,
          onNudge: widget.editing ? _nudge : null,
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
        if (!_pendingDeletes.contains(row.id)) _withPendingLayout(row),
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

  DashboardWidget _withPendingLayout(DashboardWidget row) {
    final pending = _pendingLayout[row.id];
    if (pending == null) return row;
    if (row.options == pending.options && row.width == pending.width) {
      _pendingLayout.remove(row.id);
      return row;
    }
    return row.copyWith(options: pending.options, width: pending.width);
  }

  void _selectItem(DashboardViewItem item) {
    setState(() => _selectedId = item.row.id);
  }

  /// The manual grid resolved from the current local order, with the legacy
  /// auto-flow used for any widget that predates manual placement.
  DashboardGridLayout _currentLayout() {
    return DashboardGridLayout.fromPlacements(
      resolvePlacements([
        for (final row in _ordered)
          PlacementInput(
            id: row.id,
            width: DashboardWidth.fromWire(row.width) ?? DashboardWidth.full,
            coord: dashboardLayoutFromOptions(row.options),
          ),
      ]),
    );
  }

  void _placeInCell(String draggedId, int row, int col, DashboardWidth width) {
    _applyLayout(
      _currentLayout().place(draggedId, row, col, width: width),
      draggedId,
    );
  }

  void _swap(String draggedId, String targetId) {
    _applyLayout(_currentLayout().swap(draggedId, targetId), draggedId);
  }

  void _insertRow(String draggedId, int rowIndex) {
    _applyLayout(_currentLayout().insertRowAt(draggedId, rowIndex), draggedId);
  }

  void _nudge(DashboardViewItem item, DashboardMoveDirection direction) {
    _applyLayout(_currentLayout().nudge(item.row.id, direction), item.row.id);
  }

  void _changeWidth(DashboardViewItem item, DashboardWidth width) {
    if (item.spec.width == width) return;
    _applyLayout(_currentLayout().resize(item.row.id, width), item.row.id);
  }

  /// Persists a [next] layout snapshot: reorders `_ordered` to row-major,
  /// writes each widget's `{row, col}` into its options, and saves all in one
  /// transaction. A null [next] means the move was invalid — no-op. Optimistic
  /// with rollback on failure.
  Future<void> _applyLayout(DashboardGridLayout? next, String selectId) async {
    if (next == null) return;

    final byId = {for (final row in _ordered) row.id: row};
    final entries =
        <({String id, String options, int position, String width})>[];
    final reordered = <DashboardWidget>[];
    for (var i = 0; i < next.placements.length; i++) {
      final placement = next.placements[i];
      final existing = byId[placement.id];
      if (existing == null) continue;
      final options = writeDashboardLayout(
        existing.options,
        DashboardLayoutCoord(row: placement.row, col: placement.col),
      );
      final width = placement.width.wire;
      entries.add((
        id: placement.id,
        options: options,
        position: i,
        width: width,
      ));
      reordered.add(existing.copyWith(options: options, width: width));
    }

    final previousOrdered = [..._ordered];
    final previousPending = {..._pendingLayout};
    setState(() {
      _ordered = reordered;
      for (final entry in entries) {
        _pendingLayout[entry.id] = (options: entry.options, width: entry.width);
      }
      _selectedId = selectId;
    });

    try {
      await context.read<AppRepositories>().dashboard.applyLayout(entries);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _ordered = previousOrdered;
        _pendingLayout
          ..clear()
          ..addAll(previousPending);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar el tablero: $error')),
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
