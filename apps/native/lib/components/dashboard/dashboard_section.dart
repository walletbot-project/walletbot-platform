import 'dart:async';

import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/components/dashboard/add_widget_sheet.dart';
import 'package:app/components/dashboard/dashboard_layout.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/components/dashboard/dashboard_view.dart';
import 'package:app/data/data.dart';
import 'package:app/data/queries/stream_utils.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:app/sync/sync_status.dart';
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
  AppRepositories? _repos;
  Stream<(List<DashboardWidget>, List<SavedFilter>)>? _dashboardStream;
  final _pendingDeletes = <String>{};
  // Optimistic layout writes awaiting their stream round-trip, keyed by widget
  // id. Each holds the exact `options` (carrying the new `{row, col}`) and
  // `width` we wrote, so a stream re-emit doesn't flicker back to stale content
  // before the write lands. Cleared once the incoming row matches.
  final _pendingLayout = <String, ({String options, String width})>{};
  int? _repairScheduledFor;
  bool _repairInFlight = false;
  bool _repairEnabled = false;
  List<DashboardWidget>? _queuedRepairSnapshot;
  String? _selectedId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repos = context.read<AppRepositories>();
    if (identical(_repos, repos)) return;
    _repos = repos;
    _dashboardStream = combineLatest2(
      repos.dashboard.watchWidgets(),
      repos.savedFilters.watchActive(),
      (List<DashboardWidget> widgets, List<SavedFilter> filters) =>
          (widgets, filters),
    );
  }

  @override
  void didUpdateWidget(DashboardSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editing && !widget.editing) {
      _selectedId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repos = _repos!;
    final accountType = context.read<AuthController>().activeAccount?.type;
    final syncStatus = context.watch<SyncEngine>().status;
    final canPersistRepair =
        accountType == AccountType.local || syncStatus == SyncStatus.synced;
    return StreamBuilder<(List<DashboardWidget>, List<SavedFilter>)>(
      stream: _dashboardStream,
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        if (snapshot.hasError) {
          return Text(
            context.l10n.dashboardLoadFailed,
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
        _scheduleLayoutRepair(widgets, enabled: canPersistRepair);
        if (widgets.isEmpty) {
          return Text(
            context.l10n.dashboardEmpty,
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
          onInsertInRow: widget.editing ? _insertInRow : null,
          onAddWidget: widget.editing ? _addWidgetAt : null,
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

  void _scheduleLayoutRepair(
    List<DashboardWidget> widgets, {
    required bool enabled,
  }) {
    _repairEnabled = enabled;
    if (!enabled || widgets.isEmpty) {
      _repairScheduledFor = null;
      _queuedRepairSnapshot = null;
      return;
    }
    if (_repairInFlight) {
      // Re-check the newest stream value after the active compare-and-write.
      // It may be the snapshot that made that write correctly return false.
      _queuedRepairSnapshot = List.unmodifiable(widgets);
      return;
    }
    final resolution = resolvePlacementSnapshot(_placementInputs(widgets));
    if (!resolution.needsRepair) {
      _repairScheduledFor = null;
      return;
    }

    final fingerprint = Object.hashAll([
      for (final row in widgets) ...[
        row.id,
        row.options,
        row.width,
        row.updatedAt,
      ],
    ]);
    if (_repairScheduledFor == fingerprint) return;
    _repairScheduledFor = fingerprint;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_repairEnabled || _repairScheduledFor != fingerprint) {
        return;
      }
      unawaited(_repairLayout(widgets, resolution, fingerprint));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _repairLayout(
    List<DashboardWidget> observed,
    PlacementResolution resolution,
    int fingerprint,
  ) async {
    if (_repairInFlight) return;
    _repairInFlight = true;
    _queuedRepairSnapshot = null;
    final normalized = DashboardGridLayout.fromPlacements(
      resolution.placements,
    ).placements;
    final byId = {for (final row in observed) row.id: row};
    final entries = <DashboardLayoutEntry>[];
    for (var position = 0; position < normalized.length; position++) {
      final placement = normalized[position];
      final row = byId[placement.id];
      if (row == null) continue;
      entries.add((
        id: row.id,
        options: writeDashboardLayout(
          row.options,
          DashboardLayoutCoord(row: placement.row, col: placement.col),
        ),
        position: position,
        width: placement.width.wire,
      ));
    }
    final expected = <String, DashboardLayoutExpectation>{
      for (final row in observed)
        row.id: (
          options: row.options,
          width: row.width,
          updatedAt: row.updatedAt,
        ),
    };

    try {
      final repaired = await context
          .read<AppRepositories>()
          .dashboard
          .applyLayoutIfUnchanged(entries, expected);
      if (repaired) {
        debugPrint(
          'dashboard: repaired invalid persisted layout (${entries.length} widgets)',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('dashboard: layout repair failed: $error\n$stackTrace');
    } finally {
      _repairInFlight = false;
      if (_repairScheduledFor == fingerprint) _repairScheduledFor = null;
      final queued = _queuedRepairSnapshot;
      _queuedRepairSnapshot = null;
      if (mounted && queued != null) {
        _scheduleLayoutRepair(queued, enabled: _repairEnabled);
      }
    }
  }

  List<PlacementInput> _placementInputs(List<DashboardWidget> widgets) => [
    for (final row in widgets)
      PlacementInput(
        id: row.id,
        width: DashboardWidth.fromWire(row.width) ?? DashboardWidth.full,
        coord: dashboardLayoutFromOptions(row.options),
      ),
  ];

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
      resolvePlacements(_placementInputs(_ordered)),
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

  void _insertInRow(String draggedId, int row, int slot) {
    _applyLayout(_currentLayout().insertInRow(draggedId, row, slot), draggedId);
  }

  /// Opens the add-widget flow targeting the empty cell ([row], [col]). On a
  /// legacy board (no stored coordinates) we persist the current layout first,
  /// so the new widget's placement is honored instead of being re-derived by the
  /// auto-flow fallback. [maxUnits] caps the new widget's width to the free run.
  Future<void> _addWidgetAt(int row, int col, int maxUnits) async {
    final repos = context.read<AppRepositories>();
    final needsMigration = resolvePlacementSnapshot(
      _placementInputs(_ordered),
    ).needsRepair;
    if (needsMigration) {
      await _applyLayout(_currentLayout(), _selectedId ?? '');
      if (!mounted) return;
    }
    await showAddWidgetSheet(
      context,
      repos,
      at: DashboardLayoutCoord(row: row, col: col),
      maxUnits: maxUnits,
    );
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
        SnackBar(content: Text(context.l10n.dashboardUpdateFailed(error))),
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
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.removeWidget),
        content: Text(l10n.removeWidgetConfirmation(_titleOf(item.row))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.remove),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.widgetRemoveFailed(error))));
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
      ChartWidgetSpec(:final title) =>
        title.isEmpty ? _typeLabelOf(row) : context.l10n.dashboardTitle(title),
      null => _typeLabelOf(row),
    };
  }

  String _typeLabelOf(DashboardWidget row) {
    return context.l10n.dashboardFallbackType(WidgetType.fromWire(row.type));
  }
}
