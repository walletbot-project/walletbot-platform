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
    _switchTo(value);
    notifyListeners();
  }

  /// Tabs system back returns to, oldest first. Going to a tab drops its
  /// earlier entry, so each tab appears at most once and never the current
  /// one.
  final List<_TabVisit> _history = [];

  /// The Activity filter to put back when system back leaves the current
  /// visit, set when this visit replaced it (see
  /// [noteActivityFilterReplaced]).
  TransactionFilter? _restoreOnBack;

  bool get canGoBack => _history.isNotEmpty;

  void _switchTo(int value) {
    _history.add(_TabVisit(_index, _restoreOnBack));
    final earlier = _history.indexWhere((visit) => visit.tab == value);
    // A deduplicated visit merges into this one, so it keeps that visit's
    // restore point.
    _restoreOnBack = earlier == -1
        ? null
        : _history.removeAt(earlier).restoreOnBack;
    _index = value;
  }

  /// Returns to the previous tab, putting back the Activity filter the
  /// visit being left replaced. False when there is nothing to return to.
  bool goBack() {
    if (_history.isEmpty) return false;
    final restore = _restoreOnBack;
    final previous = _history.removeLast();
    _index = previous.tab;
    _restoreOnBack = previous.restoreOnBack;
    if (restore != null) _pendingActivityFilter = restore;
    notifyListeners();
    return true;
  }

  /// Called by Activity when a filter handed in from another surface
  /// replaces its own, so back can put [previous] back. A visit that replaces
  /// it more than once keeps the first one. Restores themselves land while
  /// another tab is current and are not recorded.
  void noteActivityFilterReplaced(TransactionFilter previous) {
    if (_index != activityTab) return;
    _restoreOnBack ??= previous;
  }

  TransactionFilter? _pendingActivityFilter;

  /// Switches to the Activity tab, staging a filter that shows only the given
  /// account's transactions. The Activity screen consumes it via
  /// [takePendingActivityFilter].
  void openActivityForAccount(String accountId) {
    _openActivityWith(TransactionFilter(accountIds: {accountId}));
  }

  /// Switches to the Activity tab, staging a filter that shows only the given
  /// category's transactions.
  void openActivityForCategory(String categoryId) {
    _openActivityWith(TransactionFilter(categoryIds: {categoryId}));
  }

  /// Switches to the Activity tab, staging a filter that shows only the
  /// transactions carrying the given tag.
  void openActivityForTag(String tagId) {
    _openActivityWith(TransactionFilter(tagIds: {tagId}));
  }

  void _openActivityWith(TransactionFilter filter) {
    _pendingActivityFilter = filter;
    if (_index != activityTab) _switchTo(activityTab);
    notifyListeners();
  }

  /// Returns and clears the filter staged for the Activity tab, if any.
  TransactionFilter? takePendingActivityFilter() {
    final filter = _pendingActivityFilter;
    _pendingActivityFilter = null;
    return filter;
  }
}

class _TabVisit {
  const _TabVisit(this.tab, this.restoreOnBack);

  final int tab;
  final TransactionFilter? restoreOnBack;
}
