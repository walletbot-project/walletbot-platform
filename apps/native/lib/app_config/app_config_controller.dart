import 'dart:convert';

import 'package:app/app_config/client_info.dart';
import 'package:app/auth/account.dart';
import 'package:app/config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _configCacheKey = 'native_config_verdict';

@immutable
class AppConfigBannerAction {
  const AppConfigBannerAction({required this.label, required this.url});

  final String label;
  final String url;

  static AppConfigBannerAction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label'];
    final url = raw['url'];
    if (label is! String || label.trim().isEmpty) return null;
    if (url is! String || url.trim().isEmpty) return null;
    return AppConfigBannerAction(label: label, url: url);
  }
}

@immutable
class AppConfigBanner {
  const AppConfigBanner({
    required this.key,
    required this.index,
    required this.placements,
    required this.tone,
    required this.title,
    required this.messageMarkdown,
    required this.actions,
  });

  final String key;
  final int index;
  final List<String> placements;
  final String tone;
  final String title;
  final String messageMarkdown;
  final List<AppConfigBannerAction> actions;

  bool showsIn(String placement) => placements.contains(placement);

  static AppConfigBanner hardVersionFallback() => const AppConfigBanner(
    key: 'hard-version-update',
    index: 0,
    placements: ['home', 'auth'],
    tone: 'critical',
    title: 'Actualizacion requerida',
    messageMarkdown: 'Actualiza la app para seguir sincronizando tus datos.',
    actions: [],
  );

  static AppConfigBanner? softVersionFallback(String? updateUrl) {
    final actions = updateUrl == null || updateUrl.trim().isEmpty
        ? const <AppConfigBannerAction>[]
        : [AppConfigBannerAction(label: 'Actualizar', url: updateUrl)];
    return AppConfigBanner(
      key: 'soft-version-update',
      index: 100,
      placements: const ['home', 'auth'],
      tone: 'info',
      title: 'Nueva version disponible',
      messageMarkdown:
          'Actualiza cuando puedas para recibir **las ultimas mejoras**.',
      actions: actions,
    );
  }

  static AppConfigBanner? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'] ?? raw['id'];
    final index = raw['index'];
    final tone = raw['tone'];
    final title = raw['title'];
    final message = raw['messageMarkdown'] ?? raw['message'];
    if (key is! String || key.trim().isEmpty) return null;
    if (tone is! String || tone.trim().isEmpty) return null;
    if (title is! String || title.trim().isEmpty) return null;
    if (message is! String || message.trim().isEmpty) return null;

    final rawPlacements = raw['placements'];
    final placements = rawPlacements is List
        ? rawPlacements.whereType<String>().toList(growable: false)
        : raw['placement'] is String
        ? [raw['placement'] as String]
        : const <String>[];
    if (placements.isEmpty) return null;

    final rawActions = raw['actions'];
    final actions = rawActions is List
        ? rawActions
              .map(AppConfigBannerAction.fromJson)
              .whereType<AppConfigBannerAction>()
              .toList(growable: false)
        : const <AppConfigBannerAction>[];

    return AppConfigBanner(
      key: key,
      index: index is num ? index.round() : 0,
      placements: placements,
      tone: tone,
      title: title,
      messageMarkdown: message,
      actions: actions,
    );
  }
}

/// Fetches native config from `/v1/config` and `/v1/account-config`.
///
/// State lives outside the per-user database. Device config is loaded first;
/// account config overlays it when an active account is available. Always fails
/// open: on any error the app stays supported and usable offline. An
/// unsupported client keeps working offline; only sync is gated off.
///
/// [loaded] flips as soon as the last-good verdict is restored from cache (or
/// fail-open defaults apply), before network I/O, so sync startup cannot hang on
/// a slow config fetch. Server-side sync checks are the hard backstop.
class AppConfigController extends ChangeNotifier {
  AppConfigController({
    ClientInfo? clientInfo,
    FlutterSecureStorage? storage,
    http.Client? httpClient,
  }) : _clientInfo =
           clientInfo ??
           const ClientInfo(
             platform: 'unknown',
             appVersion: '0.0.0',
             deviceId: 'unknown',
           ),
       _storage = storage ?? const FlutterSecureStorage(),
       _http = httpClient ?? http.Client();

  final ClientInfo _clientInfo;
  final FlutterSecureStorage _storage;
  final http.Client _http;

  bool _loaded = false;
  bool _supported = true; // fail open
  bool _updateAvailable = false;
  String? _updateUrl;
  List<AppConfigBanner> _deviceBanners = const [];
  List<AppConfigBanner> _accountBanners = const [];
  String? _accountScopeKey;
  // Scope whose successful result is currently held in [_accountBanners], and
  // the scope of an in-flight fetch. Together they dedup the repeated
  // `loadAccount` calls the auth listener fires on every notification (token
  // refresh, reauth) for the same account.
  String? _accountBannersScope;
  String? _accountFetchInFlight;

  bool get loaded => _loaded;
  bool get supported => _supported;
  bool get updateAvailable => _updateAvailable;
  String? get updateUrl => _updateUrl;
  List<AppConfigBanner> get banners => _mergeBanners(
    deviceBanners: _deviceBanners,
    accountBanners: _accountBanners,
  );

  /// Sync is allowed only for supported clients.
  bool get syncAllowed => _supported;

  /// A hard update prompt: sync is gated off, but local/offline use continues.
  bool get updateRequired => !_supported;

  Future<void> load() async {
    final platform = _clientInfo.platform;
    final appVersion = _clientInfo.appVersion;
    final deviceId = _clientInfo.deviceId;

    await _restoreCachedVerdict(appVersion);
    _loaded = true;
    notifyListeners();

    await _loadVerdict(
      platform: platform,
      appVersion: appVersion,
      deviceId: deviceId,
    );
  }

  Future<void> loadAccount(UserAccount? account) async {
    final scopeKey = _scopeKey(account);
    if (_accountScopeKey != scopeKey) {
      _accountScopeKey = scopeKey;
      _accountBanners = const [];
      _accountBannersScope = null;
      notifyListeners();
    }
    if (account == null) return;

    // Dedup: skip if this scope's result is already loaded or a fetch for it is
    // already in flight. A scope change clears both markers above, so switching
    // accounts still refetches. Failures leave the markers unset, so a transient
    // error is retried on the next notification.
    if (_accountBannersScope == scopeKey ||
        _accountFetchInFlight == scopeKey) {
      return;
    }
    _accountFetchInFlight = scopeKey;

    final uri = Uri.parse('${AppConfig.convexSiteUrl}/v1/account-config');
    try {
      final resp = await _http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'platform': _clientInfo.platform,
              'appVersion': _clientInfo.appVersion,
              'deviceId': _clientInfo.deviceId,
              'account': _accountPayload(account),
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (_accountScopeKey != scopeKey) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(resp.body) as Map<String, Object?>;
        _accountBanners = _parseBanners(data, allowVersionFallback: false);
        _accountBannersScope = scopeKey;
        notifyListeners();
        return;
      }
      debugPrint('config: account HTTP ${resp.statusCode}: ${resp.body}');
    } catch (e) {
      debugPrint('config: account fetch failed: $e');
    } finally {
      if (_accountFetchInFlight == scopeKey) _accountFetchInFlight = null;
    }
  }

  /// Called when the server rejects sync with `client_outdated`. The client
  /// slipped past the client-side gate, but the backend says it is below the
  /// supported floor. Reflect that so the hard update banner shows.
  void markUnsupported() {
    if (!_supported) return;
    _supported = false;
    if (!_deviceBanners.any((banner) => banner.key == 'hard-version-update')) {
      _deviceBanners = [
        AppConfigBanner.hardVersionFallback(),
        ..._deviceBanners,
      ];
    }
    notifyListeners();
  }

  Future<void> _loadVerdict({
    required String platform,
    required String appVersion,
    required String deviceId,
  }) async {
    final uri = Uri.parse('${AppConfig.convexSiteUrl}/v1/config').replace(
      queryParameters: {
        'platform': platform,
        'appVersion': appVersion,
        'deviceId': deviceId,
      },
    );
    try {
      final resp = await _http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final verdict = jsonDecode(resp.body) as Map<String, Object?>;
        _applyVerdict(verdict);
        // Cache the verdict for this build only. A previous build's verdict
        // says nothing about whether the current build is supported.
        await _storage.write(
          key: _configCacheKey,
          value: jsonEncode({'appVersion': appVersion, 'verdict': verdict}),
        );
        notifyListeners();
        return;
      }
      debugPrint('config: verdict HTTP ${resp.statusCode}: ${resp.body}');
    } catch (e) {
      debugPrint('config: verdict fetch failed: $e');
    }
    // Keep whatever the cache restored, or the fail-open defaults.
  }

  Future<void> _restoreCachedVerdict(String appVersion) async {
    try {
      final cached = await _storage.read(key: _configCacheKey);
      if (cached == null || cached.isEmpty) return;
      final env = jsonDecode(cached) as Map<String, Object?>;
      if (env['appVersion'] != appVersion) return;
      final verdict = env['verdict'];
      if (verdict is Map<String, Object?>) _applyVerdict(verdict);
    } catch (e) {
      debugPrint('config: restore cached verdict failed: $e');
    }
  }

  void _applyVerdict(Map<String, Object?> data) {
    _supported = data['supported'] as bool? ?? true;
    _updateAvailable = data['updateAvailable'] as bool? ?? false;
    _updateUrl = data['updateUrl'] as String?;
    _deviceBanners = _parseBanners(data, allowVersionFallback: true);
  }

  List<AppConfigBanner> _parseBanners(
    Map<String, Object?> data, {
    required bool allowVersionFallback,
  }) {
    final rawBanners = data['banners'];
    if (rawBanners is List) {
      final banners = rawBanners
          .map(AppConfigBanner.fromJson)
          .whereType<AppConfigBanner>()
          .toList(growable: false);
      if (banners.isNotEmpty) return banners;
    }

    final legacyBanner = AppConfigBanner.fromJson(data['banner']);
    if (legacyBanner != null) return [legacyBanner];

    if (!allowVersionFallback) return const [];
    if (!_supported) return [AppConfigBanner.hardVersionFallback()];
    if (_updateAvailable) {
      final fallback = AppConfigBanner.softVersionFallback(_updateUrl);
      if (fallback != null) return [fallback];
    }
    return const [];
  }

  Map<String, Object?> _accountPayload(UserAccount account) {
    if (account.type == AccountType.remote) {
      return {'type': 'remote', 'token': account.sessionToken};
    }
    return {'type': 'local', 'id': account.id, 'name': account.name};
  }

  String? _scopeKey(UserAccount? account) {
    if (account == null) return null;
    return '${account.type.name}:${account.id}';
  }

  List<AppConfigBanner> _mergeBanners({
    required List<AppConfigBanner> deviceBanners,
    required List<AppConfigBanner> accountBanners,
  }) {
    final byKey = <String, AppConfigBanner>{};
    for (final banner in deviceBanners) {
      byKey[banner.key] = banner;
    }
    for (final banner in accountBanners) {
      byKey[banner.key] = banner;
    }
    final merged = byKey.values.toList();
    merged.sort((a, b) {
      final byIndex = a.index.compareTo(b.index);
      if (byIndex != 0) return byIndex;
      return a.key.compareTo(b.key);
    });
    return List.unmodifiable(merged);
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
