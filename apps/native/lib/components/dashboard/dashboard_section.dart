import 'package:app/components/dashboard/dashboard_editor.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/components/dashboard/dashboard_view.dart';
import 'package:app/data/data.dart';
import 'package:app/data/queries/stream_utils.dart';
import 'package:app/database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Reactive source for the home dashboard: joins the persisted widget rows with
/// the saved filters they reference and resolves each into a renderable spec,
/// then hands the ordered list to [DashboardView] (or, in [editing] mode, to
/// the reorder/width/delete [DashboardEditor]). Re-emits on any local write or
/// sync merge to either table.
class DashboardSection extends StatelessWidget {
  const DashboardSection({super.key, this.editing = false});

  final bool editing;

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
        if (widgets.isEmpty) {
          return Text(
            'Tu tablero está vacío. Agregá un widget para empezar.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }

        final filtersById = {for (final f in filters) f.id: f};

        if (editing) {
          return DashboardEditor(
            widgets: widgets,
            filtersById: filtersById,
            repos: repos,
          );
        }

        final specs = widgets
            .map((w) => dashboardSpecFromRow(w, filtersById))
            .whereType<DashboardWidgetSpec>()
            .toList();
        return DashboardView(widgets: specs);
      },
    );
  }
}
