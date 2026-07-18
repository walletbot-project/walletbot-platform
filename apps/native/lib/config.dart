import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App configuration.
///
/// Backend URLs are resolved in two layers:
///   1. Bundled defaults from `--dart-define` (wins) or the `.env` asset.
///   2. L0 bootstrap: `resolveBackendConfig` (see `app_config/bootstrap.dart`)
///      fetches `{ backendUrl, siteUrl }` from `BOOTSTRAP_URL` or the default
///      bootstrap URL at startup and overrides the bundled values, so the
///      backend can move without an app update. It fails open — on any error it
///      keeps the last-good cached value, else the bundled value.
///
/// In debug/profile builds, explicitly configured backend URLs are treated as a
/// local dev override and bootstrap is skipped. Release builds always try
/// bootstrap first.
///
/// Every consumer reads [convexUrl] / [convexSiteUrl], so the L0 override is
/// transparent to auth, sync and the voice agent.
class AppConfig {
  static const _convexUrlDefine = String.fromEnvironment('CONVEX_URL');
  static const _convexSiteUrlDefine = String.fromEnvironment('CONVEX_SITE_URL');
  static const _googleServerClientIdDefine = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static const _bootstrapUrlDefine = String.fromEnvironment('BOOTSTRAP_URL');
  static const _defaultBootstrapUrl =
      'https://app.walletbot.live/_native/bootstrap.json';

  static String get _bundledConvexUrl =>
      _convexUrlDefine.isNotEmpty ? _convexUrlDefine : dotenv.get('CONVEX_URL');

  static String get _bundledConvexSiteUrl => _convexSiteUrlDefine.isNotEmpty
      ? _convexSiteUrlDefine
      : dotenv.get('CONVEX_SITE_URL');

  // Runtime-resolved URLs; null until (and unless) L0 bootstrap overrides them.
  static String? _runtimeConvexUrl;
  static String? _runtimeConvexSiteUrl;

  static String get convexUrl => _runtimeConvexUrl ?? _bundledConvexUrl;
  static String get convexSiteUrl =>
      _runtimeConvexSiteUrl ?? _bundledConvexSiteUrl;

  static String get googleServerClientId =>
      _googleServerClientIdDefine.isNotEmpty
      ? _googleServerClientIdDefine
      : dotenv.get('GOOGLE_SERVER_CLIENT_ID');

  /// The L0 bootstrap endpoint.
  static String get bootstrapUrl {
    if (_bootstrapUrlDefine.isNotEmpty) return _bootstrapUrlDefine;
    final fromEnv = dotenv.maybeGet('BOOTSTRAP_URL');
    return (fromEnv != null && fromEnv.isNotEmpty)
        ? fromEnv
        : _defaultBootstrapUrl;
  }

  /// Whether `.env` or `--dart-define` explicitly provides both backend URLs.
  static bool get hasConfiguredBackendUrls {
    final defineUrls =
        _isConfigured(_convexUrlDefine) && _isConfigured(_convexSiteUrlDefine);
    final envUrls =
        _isConfigured(dotenv.maybeGet('CONVEX_URL')) &&
        _isConfigured(dotenv.maybeGet('CONVEX_SITE_URL'));
    return defineUrls || envUrls;
  }

  /// Override the backend URLs at runtime (called by L0 bootstrap).
  static void setRuntimeUrls({
    required String backendUrl,
    required String siteUrl,
  }) {
    _runtimeConvexUrl = backendUrl;
    _runtimeConvexSiteUrl = siteUrl;
  }

  static bool _isConfigured(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    return trimmed.isNotEmpty && !trimmed.contains('<');
  }
}

Future<void> loadAppConfig() async {
  await dotenv.load(fileName: '.env');
}
