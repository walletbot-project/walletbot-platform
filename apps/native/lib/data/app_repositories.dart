import '../database.dart';
import 'entity_resolver.dart';
import 'repositories/account_repository.dart';
import 'repositories/category_repository.dart';
import 'repositories/dashboard_repository.dart';
import 'repositories/saved_filter_repository.dart';
import 'repositories/summary_repository.dart';
import 'repositories/tag_repository.dart';
import 'repositories/transaction_repository.dart';

/// The app-facing data layer bundle. Registered account-scoped in main.dart
/// (inside the `ValueKey(account.id)` provider subtree) so it is created and
/// disposed together with the per-user database — repositories themselves
/// hold no state.
///
/// Screens: `context.read<AppRepositories>()` + `StreamBuilder` on a
/// repository `watch*` stream. Agent tools receive this bundle instead of the
/// raw database.
class AppRepositories {
  AppRepositories(AppDatabase db)
    : accounts = AccountRepository(db),
      categories = CategoryRepository(db),
      tags = TagRepository(db),
      transactions = TransactionRepository(db),
      summaries = SummaryRepository(db),
      savedFilters = SavedFilterRepository(db),
      dashboard = DashboardRepository(db),
      resolver = EntityResolver(db);

  final AccountRepository accounts;
  final CategoryRepository categories;
  final TagRepository tags;
  final TransactionRepository transactions;
  final SummaryRepository summaries;
  final SavedFilterRepository savedFilters;
  final DashboardRepository dashboard;
  final EntityResolver resolver;
}
