import 'package:app/convex/convex_client.dart';
import 'package:app/settings/display_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Reports this device's language to the backend, which needs one to send
/// email (and eventually WhatsApp) in.
///
/// One-way, on purpose. The display language stays device-scoped in
/// [DisplaySettingsController] and never follows the account: this only tells
/// the server what to *address* the user in. The precedence rule lives on the
/// server (`resolveLanguageWrite`): a `device` report never overwrites a
/// language the user picked by hand on some other client, and picking "System"
/// here is how they hand control back to the OS.
///
/// Account-scoped like [DefaultCurrencyController]: [isRemote] gates all
/// network I/O, since a local-only account has no backend user to own the
/// setting, and callers must create a fresh instance per account.
///
/// Never throws and never blocks. The last successfully pushed tag is cached
/// per account, so an unchanged language costs nothing on later launches and a
/// failed push simply retries at the next start or the next language change.
class LanguageSyncController {
  LanguageSyncController({
    required this.accountId,
    required this.isRemote,
    required DisplaySettingsController displaySettings,
    ConvexClient? client,
    FlutterSecureStorage? storage,
  }) : _displaySettings = displaySettings,
       _client = client,
       _storage = storage ?? const FlutterSecureStorage();

  final String accountId;
  final bool isRemote;
  final DisplaySettingsController _displaySettings;
  // Only ever touched when `isRemote` is true, so local accounts (and widget
  // tests) can run without a Convex transport.
  final ConvexClient? _client;
  ConvexClient get _resolvedClient {
    final client = _client;
    if (client == null) throw StateError('languageSync: no ConvexClient');
    return client;
  }

  final FlutterSecureStorage _storage;

  String get _cacheKey => 'language_pushed_$accountId';

  bool _started = false;

  /// Pushes the current language, then keeps pushing on every change until
  /// [dispose].
  Future<void> start() async {
    if (_started || !isRemote) return;
    _started = true;
    _displaySettings.addListener(_onSettingsChanged);
    await _push();
  }

  void dispose() {
    if (!_started) return;
    _displaySettings.removeListener(_onSettingsChanged);
    _started = false;
  }

  void _onSettingsChanged() {
    // Fires for theme changes too; `_push` no-ops when the tag is unchanged.
    _push().ignore();
  }

  Future<void> _push() async {
    final tag = _displaySettings.localeTag;
    // `system` means "whatever the OS says", which is exactly the report the
    // server treats as overwritable.
    final source = _displaySettings.language == DisplayLanguage.system
        ? 'device'
        : 'explicit';
    final key = '$source:$tag';

    try {
      if (await _storage.read(key: _cacheKey) == key) return;
    } catch (e) {
      // Unreadable cache just means we push again, which is harmless.
      debugPrint('languageSync: read cache failed: $e');
    }

    try {
      await _resolvedClient.mutation<Object?>(
        'v1/users/mutations:updateLanguage',
        {'tag': tag, 'source': source},
      );
      await _storage.write(key: _cacheKey, value: key);
    } catch (e) {
      // Offline, unauthenticated, or the mutation failed. The language the
      // user sees is already correct, so this only delays what the server
      // knows, and the next start retries.
      debugPrint('languageSync: push failed: $e');
    }
  }
}
