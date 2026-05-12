import 'package:app/screens/components/categories_view.dart';
import 'package:app/screens/components/tags_view.dart';
import 'package:flutter/material.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Insights'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Categories'),
              Tab(text: 'Tags'),
            ],
          ),
        ),
        body: const TabBarView(children: [CategoriesView(), TagsView()]),
      ),
    );
  }
}
