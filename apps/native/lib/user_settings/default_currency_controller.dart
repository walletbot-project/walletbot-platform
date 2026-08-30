import 'package:app/convex/convex_client.dart';
import 'package:app/widgets/currency_picker.dart' show kDefaultCurrency;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The user's default currency: used to prefill account creation and as the
/// bot's tie-break when two accounts share a name in different currencies.
///
/// Cache-first, fails open to [kDefaultCurrency] — mirrors
/// `AppConfigController`'s pattern for `/v1/config`
/// (`app_config/app_config_controller.dart`). Unlike that config, this value
/// comes from an *authenticated* Convex query/mutation
/// (`v1/users/queries:getSettings` / `v1/users/mutations:updateDefaultCurrency`),
/// so it is only ever fetched/persisted remotely for remote accounts — a local
/// account has no backend user to own the setting, so [isRemote] gates all
/// network I/O and the value stays a purely device-local cache for it.
///
/// Scoped per account: the cache key includes [accountId], and callers must
/// create a fresh instance per account (the same subtree that recreates
/// `AppDatabase`/`AppRepositories` on account switch) so a stale value never
/// leaks across accounts.
class DefaultCurrencyController extends ChangeNotifier {
  DefaultCurrencyController({
    required this.accountId,
    required this.isRemote,
    ConvexClient? client,
    FlutterSecureStorage? storage,
  }) : _client = client,
       _storage = storage ?? const FlutterSecureStorage();

  final String accountId;
  final bool isRemote;
  // Only ever touched when `isRemote` is true, so local accounts (and widget
  // tests) can run without a Convex transport.
  final ConvexClient? _client;
  ConvexClient get _resolvedClient {
    final client = _client;
    if (client == null) throw StateError('defaultCurrency: no ConvexClient');
    return client;
  }

  final FlutterSecureStorage _storage;

  String _value = kDefaultCurrency;
  String get value => _value;

  // Set for the duration of `setValue()` so a concurrent `_refresh()` never
  // overwrites the user's just-made choice with a stale backend value.
  bool _setValueInProgress = false;

  String get _cacheKey => 'default_currency_$accountId';

  /// Restores the cached value immediately, then (for remote accounts)
  /// refreshes from the backend in the background. Never throws — startup
  /// and offline use must never block or break on this.
  Future<void> load() async {
    try {
      final cached = await _storage.read(key: _cacheKey);
      if (cached != null && cached.isNotEmpty) {
        _value = cached;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('defaultCurrency: read cache failed: $e');
    }
    if (!isRemote) return;
    await _refresh();
  }

  Future<void> _refresh() async {
    try {
      if (_setValueInProgress) return;
      final decoded = await _resolvedClient.query<Object?>(
        'v1/users/queries:getSettings',
        const {},
      );
      if (_setValueInProgress) return;
      if (decoded is Map && decoded['defaultCurrency'] is String) {
        final next = decoded['defaultCurrency'] as String;
        if (_setValueInProgress) return;
        await _storage.write(key: _cacheKey, value: next);
        if (next != _value) {
          _value = next;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('defaultCurrency: fetch failed: $e');
    }
  }

  /// Sets the default currency. Updates the local value/cache immediately;
  /// for remote accounts also persists to the backend and rolls back on
  /// failure — this only runs from an explicit Settings save (not a
  /// background path), so surfacing the failure to the caller is correct.
  Future<void> setValue(String currency) async {
    final previous = _value;
    _setValueInProgress = true;
    _value = currency;
    notifyListeners();
    try {
      await _storage.write(key: _cacheKey, value: currency);
      if (isRemote) {
        await _resolvedClient.mutation<Object?>(
          'v1/users/mutations:updateDefaultCurrency',
          {'currency': currency},
        );
      }
    } catch (e) {
      _value = previous;
      notifyListeners();
      try {
        await _storage.write(key: _cacheKey, value: previous);
      } catch (_) {
        // Cache rollback is best-effort; the in-memory value above is
        // already correct, and a stale write here is recoverable next
        // successful `_refresh()`.
      }
      rethrow;
    } finally {
      _setValueInProgress = false;
    }
  }
}
