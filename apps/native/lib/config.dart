class AppConfig {
  static const convexUrl = String.fromEnvironment(
    'CONVEX_URL',
    defaultValue: 'https://proficient-finch-671.convex.cloud',
  );

  static const convexSiteUrl = String.fromEnvironment(
    'CONVEX_SITE_URL',
    defaultValue: 'https://proficient-finch-671.convex.site',
  );

  // Web OAuth client ID — used as audience for Google ID tokens on both platforms.
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '885078793236-a9es85agobrqq27ft5o3ks9j66jnfnsg.apps.googleusercontent.com',
  );

  static String get betterAuthBaseUrl => '$convexSiteUrl/api/auth';
}
