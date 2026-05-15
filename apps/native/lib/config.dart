import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Loaded from `.env` (a Flutter asset) at app startup via [loadAppConfig].
/// `--dart-define` overrides win over `.env` so CI/prod builds can swap values
/// without touching the bundled .env file.
class AppConfig {
  static const _convexUrlDefine = String.fromEnvironment('CONVEX_URL');
  static const _convexSiteUrlDefine = String.fromEnvironment('CONVEX_SITE_URL');
  static const _googleServerClientIdDefine = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  static String get convexUrl =>
      _convexUrlDefine.isNotEmpty ? _convexUrlDefine : dotenv.get('CONVEX_URL');

  static String get convexSiteUrl => _convexSiteUrlDefine.isNotEmpty
      ? _convexSiteUrlDefine
      : dotenv.get('CONVEX_SITE_URL');

  static String get googleServerClientId =>
      _googleServerClientIdDefine.isNotEmpty
      ? _googleServerClientIdDefine
      : dotenv.get('GOOGLE_SERVER_CLIENT_ID');

  static String get betterAuthBaseUrl => '$convexSiteUrl/api/auth';
}

Future<void> loadAppConfig() async {
  await dotenv.load(fileName: '.env');
}
