import 'package:app/components/categories_view.dart';
import 'package:app/components/tags_view.dart';
import 'package:app/data/data.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/breakpoints.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Reaches into the categories view so the add action opens the create
  /// form through its [AdaptiveDetailView] slot: the split pane on expanded
  /// windows, a real pushed route on smaller ones — with the state-preserving
  /// resize handoffs between them.
  final GlobalKey<CategoriesViewState> _categoriesKey =
      GlobalKey<CategoriesViewState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (_tabController.indexIsChanging) return;
        setState(() {});
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleAdd() async {
    if (_tabController.index == 0) {
      _categoriesKey.currentState?.openCreate();
    } else {
      await showAddTagDialog(context, context.read<AppRepositories>().tags);
    }
  }

  /// The screen's app bar: title, the add action for the active tab, and the
  /// Categories/Tags tab bar. On small windows it heads the whole screen,
  /// exactly as it always has; on expanded windows each divided view carries
  /// its own copy at the top of the list column (the established pattern:
  /// per-column app bars, divider to the top).
  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      title: Text(context.l10n.insights),
      actions: [
        IconButton(
          tooltip: _tabController.index == 0
              ? context.l10n.newCategoryTooltip
              : context.l10n.newTagTooltip,
          onPressed: _handleAdd,
          icon: const Icon(Icons.add),
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        tabs: [
          Tab(text: context.l10n.categories),
          Tab(text: context.l10n.tags),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final split = windowSizeClassOf(context) == WindowSizeClass.expanded;
    // The Scaffold → TabBarView shape is identical in both modes so the
    // views' Elements update in place when the window crosses the breakpoint
    // and their States (selections, open forms) survive; only where the app
    // bar lives changes.
    return Scaffold(
      appBar: split ? null : _buildAppBar(context),
      body: TabBarView(
        controller: _tabController,
        children: [
          CategoriesView(
            key: _categoriesKey,
            header: split ? _buildAppBar(context) : null,
          ),
          TagsView(header: split ? _buildAppBar(context) : null),
        ],
      ),
    );
  }
}
