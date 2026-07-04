import 'package:flutter/foundation.dart';

import '../data/data.dart';

/// Cross-tab navigation state for the main scaffold's [IndexedStack].
///
/// The four tabs (Home, Activity, Accounts, Insights) stay alive in the stack,
/// so switching to a tab and handing it data can't go through a pushed route.
/// This notifier lets a screen both switch tabs and stage a filter for another
/// tab to pick up — e.g. "Ver todas" on an account opens Activity already
/// filtered to that account.
class AppNavigation extends ChangeNotifier {
  static const int homeTab = 0;
  static const int activityTab = 1;
  static const int accountsTab = 2;
  static const int insightsTab = 3;

  int _index = homeTab;
  int get index => _index;
  set index(int value) {
    if (value == _index) return;
    _index = value;
    notifyListeners();
  }

  TransactionFilter? _pendingActivityFilter;

  /// Switches to the Activity tab, staging a filter that shows only the given
  /// account's transactions. The Activity screen consumes it via
  /// [takePendingActivityFilter].
  void openActivityForAccount(String accountId) {
    _pendingActivityFilter = TransactionFilter(accountIds: {accountId});
    _index = activityTab;
    notifyListeners();
  }

  /// Switches to the Activity tab, staging a filter that shows only the given
  /// category's transactions.
  void openActivityForCategory(String categoryId) {
    _pendingActivityFilter = TransactionFilter(categoryIds: {categoryId});
    _index = activityTab;
    notifyListeners();
  }

  /// Switches to the Activity tab, staging a filter that shows only the
  /// transactions carrying the given tag.
  void openActivityForTag(String tagId) {
    _pendingActivityFilter = TransactionFilter(tagIds: {tagId});
    _index = activityTab;
    notifyListeners();
  }

  /// Returns and clears the filter staged for the Activity tab, if any.
  TransactionFilter? takePendingActivityFilter() {
    final filter = _pendingActivityFilter;
    _pendingActivityFilter = null;
    return filter;
  }
}
