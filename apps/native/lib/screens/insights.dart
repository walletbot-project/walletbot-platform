import 'package:app/components/categories_view.dart';
import 'package:app/components/tags_view.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/create_category.dart';
import 'package:app/shared/adaptive_detail_view.dart';
import 'package:app/shared/app_navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Insights: the Categories/Tags tab view with a single divided-view host.
///
/// The whole screen is ONE [AdaptiveDetailView]: its list side is the app bar
/// (title, add action, tab bar) plus the sliding tab pages, and the detail
/// pane sits OUTSIDE the tab view — so on expanded windows switching tabs
/// slides only the list column while the divider and pane stay put. The pane
/// is shared across both tabs: it holds the last thing opened (a category or
/// tag detail, or the create-category form), like the Activity and Accounts
/// panes. On small windows the host renders the list side as-is — the app
/// bar heads the whole screen and details present as real modal sheets,
/// exactly as they always have.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Selection for the shared detail pane — at most one across both tabs,
  /// last opened wins. The data layer and navigation controller are captured
  /// at open because the sheet route sits above the account-scoped providers.
  Category? _detailCategory;
  Tag? _detailTag;
  AppRepositories? _detailRepos;
  AppNavigation? _detailNav;

  /// Pins the detail's Element so its State survives moving between pane and
  /// sheet on window resize. Recreated per selection.
  GlobalKey _detailKey = GlobalKey(debugLabel: 'insightsDetail');

  /// The create-category form: split pane on expanded windows, a real pushed
  /// route on smaller ones (via [AdaptiveDetailView]'s form slot). The data
  /// layer is captured at open because the route sits above the
  /// account-scoped providers and must be re-provided.
  bool _formOpen = false;
  AppRepositories? _formRepos;
  GlobalKey _formKey = GlobalKey(debugLabel: 'categoryCreate');

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

  void _openCategoryDetails(CategoryWithCount entry) {
    setState(() {
      if (_detailTag != null || entry.category.id != _detailCategory?.id) {
        _detailKey = GlobalKey(debugLabel: 'insightsDetail');
      }
      _detailCategory = entry.category;
      _detailTag = null;
      _detailRepos = context.read<AppRepositories>();
      _detailNav = context.read<AppNavigation>();
      // The pane hosts one occupant at a time.
      _formOpen = false;
    });
  }

  void _openTagDetails(Tag tag) {
    setState(() {
      if (_detailCategory != null || tag.id != _detailTag?.id) {
        _detailKey = GlobalKey(debugLabel: 'insightsDetail');
      }
      _detailTag = tag;
      _detailCategory = null;
      _detailRepos = context.read<AppRepositories>();
      _detailNav = context.read<AppNavigation>();
      // The pane hosts one occupant at a time.
      _formOpen = false;
    });
  }

  void _closeDetails() {
    setState(() {
      _detailCategory = null;
      _detailTag = null;
    });
  }

  Widget? _buildDetail(BuildContext context, {required bool inSheet}) {
    final category = _detailCategory;
    if (category != null) {
      return CategoryDetailsSheet(
        key: _detailKey,
        category: category,
        repos: _detailRepos!,
        nav: _detailNav!,
        onClose: inSheet ? null : _closeDetails,
      );
    }
    final tag = _detailTag;
    if (tag != null) {
      return TagDetailsSheet(
        key: _detailKey,
        tag: tag,
        repos: _detailRepos!,
        nav: _detailNav!,
        onClose: inSheet ? null : _closeDetails,
      );
    }
    return null;
  }

  void _openCreate() {
    setState(() {
      _formOpen = true;
      _formRepos = context.read<AppRepositories>();
      _formKey = GlobalKey(debugLabel: 'categoryCreate');
      // The pane hosts one occupant at a time.
      _detailCategory = null;
      _detailTag = null;
    });
  }

  void _closeForm() {
    setState(() => _formOpen = false);
  }

  Widget? _buildForm(BuildContext context, {required bool inRoute}) {
    if (!_formOpen) return null;
    final form = CreateCategoryScreen(
      key: _formKey,
      onClose: inRoute ? null : _closeForm,
    );
    if (!inRoute) return form;
    // Route mode: pushed routes sit above the account-scoped providers;
    // re-provide them, exactly as the original push did. The keyed form
    // widget itself moves in/out of this wrapper on handoffs.
    return Provider<AppRepositories>.value(value: _formRepos!, child: form);
  }

  Future<void> _handleAdd() async {
    if (_tabController.index == 0) {
      _openCreate();
    } else {
      await showAddTagDialog(context, context.read<AppRepositories>().tags);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActiveTab = context.select<AppNavigation, bool>(
      (nav) => nav.index == AppNavigation.insightsTab,
    );
    return AdaptiveDetailView(
      hasDetail: _detailCategory != null || _detailTag != null,
      detailBuilder: _buildDetail,
      onSheetDismissed: _closeDetails,
      hasForm: _formOpen,
      formBuilder: _buildForm,
      onFormDismissed: _closeForm,
      isActiveTab: isActiveTab,
      placeholder: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _tabController.index == 0
                ? context.l10n.selectCategoryDetail
                : context.l10n.selectTagDetail,
            textAlign: TextAlign.center,
          ),
        ),
      ),
      list: Scaffold(
        appBar: AppBar(
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
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            CategoriesView(onSelect: _openCategoryDetails),
            TagsView(onSelect: _openTagDetails),
          ],
        ),
      ),
    );
  }
}
