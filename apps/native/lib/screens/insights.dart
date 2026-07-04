import 'package:app/components/categories_view.dart';
import 'package:app/components/tags_view.dart';
import 'package:app/data/data.dart';
import 'package:app/screens/create_category.dart';
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
    final repos = context.read<AppRepositories>();
    if (_tabController.index == 0) {
      // Pushed routes sit above the account-scoped providers; re-provide them
      // so the create screen keeps using the active account's data layer.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Provider<AppRepositories>.value(
            value: repos,
            child: const CreateCategoryScreen(),
          ),
        ),
      );
    } else {
      await showAddTagDialog(context, repos.tags);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          IconButton(
            tooltip: _tabController.index == 0 ? 'New category' : 'New tag',
            onPressed: _handleAdd,
            icon: const Icon(Icons.add),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Categories'),
            Tab(text: 'Tags'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [CategoriesView(), TagsView()],
      ),
    );
  }
}
