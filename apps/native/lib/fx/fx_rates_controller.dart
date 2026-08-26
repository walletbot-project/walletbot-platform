import 'dart:async';
import 'dart:convert';

import 'package:app/app_config/app_config_controller.dart';
import 'package:app/config.dart';
import 'package:app/voice/tool_fx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// The feature flag that turns the agent's exchange-rate tool on. Resolved
/// per user by the backend and delivered with the account config; the mint
/// applies the same flag when deciding whether to declare `getExchangeRate`.
const String kExchangeRatesFlag = 'exchangeRates';

const _fxCacheKey = 'fx_rates_snapshot';

/// Device-scoped cache of the market exchange rates the `getExchangeRate`
/// tool answers from.
///
/// Rates are public market data, not user data, so they are deliberately kept
/// out of `AppDatabase.forUser` (which is torn down on account switch) and out
/// of the sync protocol: this is an app-scoped controller backed by
/// device-scoped storage, exactly like the app config verdict.
///
/// The network hop lives here rather than in `ToolExecutors` so the executors
/// stay pure and offline-safe — they read whatever this last cached, and the
/// tool reports the quote's own `asOf` so a stale answer is still an honest
/// one. Nothing is fetched while the feature flag is off.
class FxRatesController extends ChangeNotifier {
  FxRatesController({
    required AppConfigController appConfig,
    FlutterSecureStorage? storage,
    http.Client? httpClient,
    DateTime Function()? now,
  }) : _appConfig = appConfig,
       _storage = storage ?? const FlutterSecureStorage(),
       _http = httpClient ?? http.Client(),
       _now = now ?? DateTime.now {
    _appConfig.addListener(_onConfigChanged);
  }

  /// A device refresh is cheap but pointless more often than this: the backend
  /// crons refresh the Argentine markets every 30 minutes.
  static const Duration minRefreshInterval = Duration(minutes: 15);

  static const Duration _requestTimeout = Duration(seconds: 5);

  final AppConfigController _appConfig;
  final FlutterSecureStorage _storage;
  final http.Client _http;
  final DateTime Function() _now;

  List<FxQuote> _quotes = const [];
  DateTime? _fetchedAt;
  bool _restored = false;
  Future<void>? _inFlight;

  /// The cached snapshot. Empty means "no quotes on this device", which the
  /// tool reports as unavailable rather than guessing.
  List<FxQuote> get quotes => _quotes;

  /// When this device last successfully fetched, or null if it never has.
  DateTime? get fetchedAt => _fetchedAt;

  bool get enabled => _appConfig.isFlagEnabled(kExchangeRatesFlag);

  /// Restores the cached snapshot, then refreshes if the flag allows it.
  Future<void> load() async {
    await _restoreCache();
    await refreshIfNeeded();
  }

  /// Fetches unless the flag is off, a fetch is already running, or the last
  /// one was recent. Never throws: a failure leaves the cached snapshot in
  /// place.
  Future<void> refreshIfNeeded({bool force = false}) async {
    if (!enabled) return;
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final last = _fetchedAt;
    if (!force &&
        last != null &&
        _now().difference(last) < minRefreshInterval) {
      return;
    }
    final request = _refresh();
    _inFlight = request;
    try {
      await request;
    } finally {
      _inFlight = null;
    }
  }

  void _onConfigChanged() {
    // The flag arrives with the account config, after startup. Picking it up
    // here is what makes the first session of a newly enabled user work
    // without an app restart.
    if (enabled) unawaited(refreshIfNeeded());
  }

  Future<void> _refresh() async {
    final uri = Uri.parse('${AppConfig.convexSiteUrl}/v1/fx/rates');
    try {
      final response = await _http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('fx: rates HTTP ${response.statusCode}');
        return;
      }
      final decoded = jsonDecode(response.body);
      final quotes = _parseQuotes(decoded);
      if (quotes.isEmpty) {
        debugPrint('fx: rates response carried no usable quotes');
        return;
      }
      _quotes = quotes;
      _fetchedAt = _now();
      notifyListeners();
      await _writeCache(quotes);
    } catch (e) {
      debugPrint('fx: rates fetch failed: $e');
    }
  }

  List<FxQuote> _parseQuotes(Object? decoded) {
    if (decoded is! Map) return const [];
    final raw = decoded['rates'];
    if (raw is! List) return const [];
    final quotes = <FxQuote>[];
    for (final entry in raw) {
      final quote = FxQuote.fromJson(entry);
      if (quote != null) quotes.add(quote);
    }
    return quotes;
  }

  Future<void> _restoreCache() async {
    if (_restored) return;
    _restored = true;
    try {
      final cached = await _storage.read(key: _fxCacheKey);
      if (cached == null || cached.isEmpty) return;
      final decoded = jsonDecode(cached);
      if (decoded is! Map) return;
      final quotes = _parseQuotes(decoded);
      if (quotes.isEmpty) return;
      // Only the quotes are restored, never `fetchedAt`: a cache written days
      // ago must not throttle this run's first refresh.
      _quotes = quotes;
      notifyListeners();
    } catch (e) {
      debugPrint('fx: restore cached rates failed: $e');
    }
  }

  Future<void> _writeCache(List<FxQuote> quotes) async {
    try {
      await _storage.write(
        key: _fxCacheKey,
        value: jsonEncode({
          'rates': [for (final quote in quotes) quote.toJson()],
        }),
      );
    } catch (e) {
      debugPrint('fx: cache write failed: $e');
    }
  }

  @override
  void dispose() {
    _appConfig.removeListener(_onConfigChanged);
    _http.close();
    super.dispose();
  }
}
