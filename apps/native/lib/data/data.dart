/// The app's data-access layer. See `lib/data/repositories/repository_base.dart`
/// for the write contract every repository upholds (dirty flag, tombstones,
/// transactional deletes) and how it relates to the sync engine.
library;

export 'app_repositories.dart';
export 'entity_resolver.dart';
export 'ids.dart';
export 'models/entity_counts.dart';
export 'models/summaries.dart';
export 'models/transaction_filter.dart';
export 'queries/account_balance.dart';
export 'queries/transaction_query.dart' show TxnOrdering;
export 'repositories/account_repository.dart';
export 'repositories/category_repository.dart';
export 'repositories/summary_repository.dart';
export 'repositories/tag_repository.dart';
export 'repositories/transaction_repository.dart';
export 'tombstones.dart';
