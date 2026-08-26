// The Dart half of the cross-language exchange-rate parity suite. The same
// fixture table runs against the TS originals in
// packages/shared/test/fx-fixtures.test.ts — a behavioural change on one side
// fails the other side's run until both are updated together.

import 'dart:convert';
import 'dart:io';

import 'package:app/voice/tool_fx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // flutter test runs with cwd = apps/native.
  final fixtures =
      jsonDecode(
            File(
              '../../packages/shared/src/tools/fx-fixtures.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  final nowMs = fixtures['nowMs'] as int;
  final snapshot = [
    for (final raw in fixtures['snapshot'] as List) FxQuote.fromJson(raw)!,
  ];

  Map<String, Object?> asMap(FxResolution r) => {
    'from': r.from,
    'to': r.to,
    'market': r.market,
    'rate': r.rate,
    if (r.buy != null) 'buy': r.buy,
    if (r.sell != null) 'sell': r.sell,
    'source': r.source,
    'asOf': r.asOf,
    'path': r.path,
  };

  group('resolveFxQuote fixtures', () {
    for (final raw in fixtures['resolve'] as List) {
      final c = (raw as Map).cast<String, Object?>();
      final from = c['from'] as String;
      final to = c['to'] as String;
      final market = c['market'] as String?;
      test('$from->$to${market == null ? '' : ' ($market)'}', () {
        final result = resolveFxQuote(
          snapshot,
          from,
          to,
          market ?? kDefaultFxMarket,
        );
        final expected = c['expected'];
        if (expected == null) {
          expect(result, isNull);
          return;
        }
        expect(result, isNotNull);
        // Both platforms compute in IEEE 754 doubles — the numbers are exact,
        // not approximate, so this compares them literally.
        expect(asMap(result!), (expected as Map).cast<String, Object?>());
      });
    }
  });

  group('fxAlternatives fixtures', () {
    for (final raw in fixtures['alternatives'] as List) {
      final c = (raw as Map).cast<String, Object?>();
      final from = c['from'] as String;
      final to = c['to'] as String;
      test('$from->$to', () {
        expect(
          fxAlternatives(snapshot, from, to),
          (c['expected'] as Map).cast<String, Object?>(),
        );
      });
    }
  });

  group('convertAmount fixtures', () {
    for (final raw in fixtures['convert'] as List) {
      final c = (raw as Map).cast<String, Object?>();
      final amount = (c['amount'] as num).toDouble();
      final rate = (c['rate'] as num).toDouble();
      test('$amount * $rate', () {
        expect(convertAmount(amount, rate), c['value'] as num);
      });
    }
  });

  group('isFxQuoteStale fixtures', () {
    for (final raw in fixtures['stale'] as List) {
      final c = (raw as Map).cast<String, Object?>();
      final asOf = c['asOf'] as String;
      test(asOf, () {
        expect(isFxQuoteStale(asOf, nowMs), c['expected'] as bool);
      });
    }
  });
}
