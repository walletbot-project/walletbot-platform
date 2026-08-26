// Pure helpers mirrored from packages/shared/src/tools/fx.ts. Keep in sync
// with the TS version — both implement the same contract (identical resolution
// order, market fallback, rounding and staleness) so the `getExchangeRate`
// tool answers the same thing on web and native. Parity is locked by
// packages/shared/src/tools/fx-fixtures.json, run on this side by
// test/voice/fx_fixtures_test.dart.
//
// The snapshot these work over is fetched and cached by
// lib/fx/fx_rates_controller.dart; nothing here touches the network.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The quote flavors a pair can carry. Only ARS pairs currently have more
/// than `official`.
const List<String> kFxMarkets = [
  'official',
  'blue',
  'mep',
  'ccl',
  'card',
  'crypto',
  'wholesale',
];

/// Used whenever the caller names no market, and the fallback for every pair.
const String kDefaultFxMarket = 'official';

/// A quote older than this is reported as stale. Sized to cover a long
/// weekend — see the TS original for why.
const int kFxStaleAfterMs = 72 * 60 * 60 * 1000;

const String _usd = 'USD';

bool isFxMarket(String value) => kFxMarkets.contains(value);

String normalizeCurrencyCode(String code) => code.trim().toUpperCase();

/// One cached quote: 1 [base] = [rate] [quote].
@immutable
class FxQuote {
  const FxQuote({
    required this.base,
    required this.quote,
    required this.market,
    required this.rate,
    required this.source,
    required this.asOf,
    this.buy,
    this.sell,
  });

  final String base;
  final String quote;
  final String market;
  final double rate;

  /// Provider's compra, when it publishes a two-sided price.
  final double? buy;

  /// Provider's venta, when it publishes a two-sided price.
  final double? sell;
  final String source;

  /// ISO 8601 timestamp of the provider's own "last updated".
  final String asOf;

  /// Decodes one wire row, returning null for anything malformed so a single
  /// bad row can never poison the whole cached snapshot.
  static FxQuote? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final base = raw['base'];
    final quote = raw['quote'];
    final market = raw['market'];
    final rate = raw['rate'];
    final source = raw['source'];
    final asOf = raw['asOf'];
    if (base is! String || quote is! String || source is! String) return null;
    if (market is! String || !isFxMarket(market)) return null;
    if (rate is! num || !rate.isFinite || rate <= 0) return null;
    if (asOf is! String) return null;
    final buy = raw['buy'];
    final sell = raw['sell'];
    return FxQuote(
      base: base,
      quote: quote,
      market: market,
      rate: rate.toDouble(),
      buy: buy is num && buy.isFinite ? buy.toDouble() : null,
      sell: sell is num && sell.isFinite ? sell.toDouble() : null,
      source: source,
      asOf: asOf,
    );
  }

  Map<String, Object?> toJson() => {
    'base': base,
    'quote': quote,
    'market': market,
    'rate': rate,
    if (buy != null) 'buy': buy,
    if (sell != null) 'sell': sell,
    'source': source,
    'asOf': asOf,
  };
}

@immutable
class FxResolution {
  const FxResolution({
    required this.from,
    required this.to,
    required this.market,
    required this.rate,
    required this.source,
    required this.asOf,
    required this.path,
    this.buy,
    this.sell,
  });

  final String from;
  final String to;

  /// The market actually used, which may differ from the one requested.
  final String market;
  final double rate;
  final double? buy;
  final double? sell;
  final String source;
  final String asOf;

  /// 'direct', 'inverse' or 'triangulated'.
  final String path;
}

class _Leg {
  const _Leg({
    required this.rate,
    required this.asOf,
    required this.source,
    required this.market,
  });

  final double rate;
  final String asOf;
  final String source;
  final String market;
}

int? _parseMs(String value) => DateTime.tryParse(value)?.millisecondsSinceEpoch;

String _olderOf(String left, String right) {
  final leftMs = _parseMs(left);
  final rightMs = _parseMs(right);
  if (leftMs == null) return rightMs == null ? left : right;
  if (rightMs == null) return left;
  return leftMs <= rightMs ? left : right;
}

String _joinSources(String left, String right) =>
    left == right ? left : '$left+$right';

/// The requested market first, then the official fallback (deduped).
List<String> _marketChain(String market) =>
    market == kDefaultFxMarket ? [market] : [market, kDefaultFxMarket];

FxQuote? _findQuote(
  List<FxQuote> snapshot,
  String base,
  String quote,
  String market,
) {
  for (final entry in snapshot) {
    if (entry.base == base && entry.quote == quote && entry.market == market) {
      return entry;
    }
  }
  return null;
}

/// One side of a triangulation: USD → [code], at [market] or else official.
/// There is deliberately no USD identity case — see the TS original.
_Leg? _usdLeg(List<FxQuote> snapshot, String code, String market) {
  for (final candidate in _marketChain(market)) {
    final direct = _findQuote(snapshot, _usd, code, candidate);
    if (direct != null) {
      return _Leg(
        rate: direct.rate,
        asOf: direct.asOf,
        source: direct.source,
        market: candidate,
      );
    }
    final inverse = _findQuote(snapshot, code, _usd, candidate);
    if (inverse != null && inverse.rate > 0) {
      return _Leg(
        rate: 1 / inverse.rate,
        asOf: inverse.asOf,
        source: inverse.source,
        market: candidate,
      );
    }
  }
  return null;
}

/// Resolves [fromCode] → [toCode] against a snapshot, preferring [market].
/// Returns null when neither a direct, inverse nor USD-triangulated path
/// exists.
FxResolution? resolveFxQuote(
  List<FxQuote> snapshot,
  String fromCode,
  String toCode, [
  String market = kDefaultFxMarket,
]) {
  final from = normalizeCurrencyCode(fromCode);
  final to = normalizeCurrencyCode(toCode);

  for (final candidate in _marketChain(market)) {
    final direct = _findQuote(snapshot, from, to, candidate);
    if (direct != null) {
      return FxResolution(
        from: from,
        to: to,
        market: candidate,
        rate: direct.rate,
        buy: direct.buy,
        sell: direct.sell,
        source: direct.source,
        asOf: direct.asOf,
        path: 'direct',
      );
    }
    final inverse = _findQuote(snapshot, to, from, candidate);
    if (inverse != null && inverse.rate > 0) {
      return FxResolution(
        from: from,
        to: to,
        market: candidate,
        // buy/sell are dropped: inverting a two-sided price also swaps the
        // sides, which is a subtlety the model should not have to reason
        // about. The mid rate is unambiguous.
        rate: 1 / inverse.rate,
        source: inverse.source,
        asOf: inverse.asOf,
        path: 'inverse',
      );
    }
  }

  final fromLeg = _usdLeg(snapshot, from, market);
  final toLeg = _usdLeg(snapshot, to, market);
  if (fromLeg == null || toLeg == null || fromLeg.rate <= 0) return null;
  return FxResolution(
    from: from,
    to: to,
    // The requested market survives only if a leg actually carried it.
    market: fromLeg.market == market || toLeg.market == market
        ? market
        : kDefaultFxMarket,
    rate: toLeg.rate / fromLeg.rate,
    source: _joinSources(fromLeg.source, toLeg.source),
    asOf: _olderOf(fromLeg.asOf, toLeg.asOf),
    path: 'triangulated',
  );
}

/// Every market this exact pair is quoted in (direct or inverted), so the
/// agent can name them without a second call. Empty unless the pair carries
/// more than one market.
Map<String, double> fxAlternatives(
  List<FxQuote> snapshot,
  String fromCode,
  String toCode,
) {
  final from = normalizeCurrencyCode(fromCode);
  final to = normalizeCurrencyCode(toCode);
  final result = <String, double>{};
  for (final market in kFxMarkets) {
    final direct = _findQuote(snapshot, from, to, market);
    if (direct != null) {
      result[market] = direct.rate;
      continue;
    }
    final inverse = _findQuote(snapshot, to, from, market);
    if (inverse != null && inverse.rate > 0) result[market] = 1 / inverse.rate;
  }
  return result.length > 1 ? result : <String, double>{};
}

/// Half away from zero, matching the TS mirror.
double _roundTo(double value, int digits) {
  if (!value.isFinite) return value;
  final factor = math.pow(10, digits).toDouble();
  final scaled = value * factor;
  final rounded = scaled < 0 ? -(-scaled).round() : scaled.round();
  return rounded / factor;
}

/// Converts a display-unit amount at [rate], rounded to 2 decimals.
double convertAmount(double amount, double rate) => _roundTo(amount * rate, 2);

bool isFxQuoteStale(String asOf, int nowMs) {
  final parsed = _parseMs(asOf);
  if (parsed == null) return true;
  return nowMs - parsed > kFxStaleAfterMs;
}
