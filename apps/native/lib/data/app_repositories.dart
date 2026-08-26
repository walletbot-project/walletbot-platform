import '../database.dart';
import '../telemetry/business_metrics.dart';
import '../widgets/currency_picker.dart' show kDefaultCurrency;
import 'entity_resolver.dart';
import 'repositories/account_repository.dart';
import 'repositories/agent_memory_repository.dart';
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
  AppRepositories(
    AppDatabase db, {
    BusinessMetrics? businessMetrics,
    this.defaultCurrency = _fallbackDefaultCurrency,
  }) : accounts = AccountRepository(db, businessMetrics: businessMetrics),
       categories = CategoryRepository(db),
       tags = TagRepository(db),
       transactions = TransactionRepository(
         db,
         businessMetrics: businessMetrics,
       ),
       summaries = SummaryRepository(db),
       savedFilters = SavedFilterRepository(db),
       dashboard = DashboardRepository(db),
       agentMemories = AgentMemoryRepository(db),
       resolver = EntityResolver(db, defaultCurrency);

  final AccountRepository accounts;
  final CategoryRepository categories;
  final TagRepository tags;
  final TransactionRepository transactions;
  final SummaryRepository summaries;
  final SavedFilterRepository savedFilters;
  final DashboardRepository dashboard;
  final AgentMemoryRepository agentMemories;
  final EntityResolver resolver;

  /// The user's default currency (device cache, backed by
  /// `DefaultCurrencyController` — see `user_settings/`). Used to fill in an
  /// omitted `currency` on account creation and to break name-collision ties.
  final String Function() defaultCurrency;
}

String _fallbackDefaultCurrency() => kDefaultCurrency;
