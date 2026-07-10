import 'dart:convert';

import 'package:app/components/dashboard/add_widget_sheet.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

/// Edit-mode view of the dashboard: a vertical reorderable list of tiles, each
/// with a width control and a delete action. Lives inside the home `ListView`,
/// so it shrink-wraps and delegates scrolling to the parent.
///
/// Reordering and width changes persist immediately through
/// [DashboardRepository]; the home dashboard stream then re-emits and any other
/// view (or device) reflects the change.
class DashboardEditor extends StatefulWidget {
  const DashboardEditor({
    super.key,
    required this.widgets,
    required this.filtersById,
    required this.repos,
  });

  final List<DashboardWidget> widgets;
  final Map<String, SavedFilter> filtersById;
  final AppRepositories repos;

  @override
  State<DashboardEditor> createState() => _DashboardEditorState();
}

class _DashboardEditorState extends State<DashboardEditor> {
  late List<DashboardWidget> _ordered;

  @override
  void initState() {
    super.initState();
    _ordered = [...widget.widgets];
  }

  @override
  void didUpdateWidget(DashboardEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync from the stream on every emit: refresh each row's *content* (e.g.
    // a width change) while preserving the current local order (so an in-flight
    // drag-reorder isn't clobbered before it persists). Deleted rows drop out;
    // newly added rows append.
    final incomingById = {for (final w in widget.widgets) w.id: w};
    final next = <DashboardWidget>[];
    final used = <String>{};
    for (final w in _ordered) {
      final fresh = incomingById[w.id];
      if (fresh != null) {
        next.add(fresh);
        used.add(w.id);
      }
    }
    for (final w in widget.widgets) {
      if (!used.contains(w.id)) next.add(w);
    }
    _ordered = next;
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    setState(() {
      final row = _ordered.removeAt(oldIndex);
      _ordered.insert(newIndex, row);
    });
    await widget.repos.dashboard.reorder(_ordered.map((w) => w.id).toList());
  }

  Future<void> _changeWidth(String id, DashboardWidth width) =>
      widget.repos.dashboard.update(id, width: Value(width.wire));

  Future<void> _edit(DashboardWidget row) => showEditWidgetSheet(
    context,
    widget.repos,
    row,
    dashboardFilterFromRow(row, widget.filtersById),
  );

  Future<void> _delete(DashboardWidget row) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar widget'),
        content: Text('¿Quitar "${_titleOf(row)}" del tablero?'),
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
    try {
      await widget.repos.dashboard.archive(row.id);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo quitar el widget: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: _ordered.length,
      onReorderItem: _onReorder,
      itemBuilder: (context, index) {
        final row = _ordered[index];
        return _EditTile(
          key: ValueKey(row.id),
          index: index,
          title: _titleOf(row),
          typeLabel: _typeLabelOf(row),
          width: DashboardWidth.fromWire(row.width) ?? DashboardWidth.full,
          onWidthChanged: (w) => _changeWidth(row.id, w),
          onEdit: () => _edit(row),
          onDelete: () => _delete(row),
        );
      },
    );
  }

  String _titleOf(DashboardWidget row) {
    final decoded = jsonDecode(row.options);
    if (decoded is Map && decoded['title'] is String) {
      final title = decoded['title'] as String;
      if (title.isNotEmpty) return title;
    }
    return _typeLabelOf(row);
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

class _EditTile extends StatelessWidget {
  const _EditTile({
    super.key,
    required this.index,
    required this.title,
    required this.typeLabel,
    required this.width,
    required this.onWidthChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final String title;
  final String typeLabel;
  final DashboardWidth width;
  final ValueChanged<DashboardWidth> onWidthChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_handle),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    typeLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<DashboardWidth>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: DashboardWidth.full,
                        label: Text('1/1'),
                      ),
                      ButtonSegment(
                        value: DashboardWidth.twoThirds,
                        label: Text('2/3'),
                      ),
                      ButtonSegment(
                        value: DashboardWidth.half,
                        label: Text('1/2'),
                      ),
                      ButtonSegment(
                        value: DashboardWidth.third,
                        label: Text('1/3'),
                      ),
                    ],
                    selected: {width},
                    onSelectionChanged: (s) => onWidthChanged(s.first),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Quitar',
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
