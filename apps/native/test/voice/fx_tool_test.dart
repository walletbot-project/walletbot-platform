// The getExchangeRate envelope. The resolution maths itself is covered by the
// cross-language parity suite (fx_fixtures_test.dart); what this locks is the
// protocol the prompt promises: error strings, the market fallback being
// reported, and never answering from an empty cache.

import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/voice/tool_executors.dart';
import 'package:app/voice/tool_fx.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  final snapshot = [
    FxQuote(
      base: 'USD',
      quote: 'ARS',
      market: 'official',
      rate: 1505,
      buy: 1480,
      sell: 1530,
      source: 'dolarapi',
      asOf: DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
    ),
    FxQuote(
      base: 'USD',
      quote: 'ARS',
      market: 'blue',
      rate: 1555,
      source: 'dolarapi',
      asOf: DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
    ),
  ];

  ToolExecutors executorsWith(List<FxQuote> quotes) =>
      ToolExecutors(AppRepositories(db), fxQuotes: () => quotes);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'a direct quote carries both sides, the source and the timestamp',
    () async {
      final res = await executorsWith(
        snapshot,
      ).execute('getExchangeRate', {'from': 'usd', 'to': 'ars'});
      expect(res['ok'], isTrue);
      expect(res['market'], 'official');
      expect(res['rate'], 1505);
      expect(res['buy'], 1480);
      expect(res['sell'], 1530);
      expect(res['path'], 'direct');
      expect(res['source'], 'dolarapi');
      expect(res.containsKey('stale'), isFalse);
      // Both Argentine quotes come back, so the agent can name them unprompted.
      expect(res['alternatives'], {'official': 1505.0, 'blue': 1555.0});
    },
  );

  test('an amount is converted at the resolved rate', () async {
    final res = await executorsWith(snapshot).execute('getExchangeRate', {
      'from': 'USD',
      'to': 'ARS',
      'market': 'blue',
      'amount': 10,
    });
    expect(res['market'], 'blue');
    expect(res['converted'], 15550.0);
  });

  test('a market the pair does not publish falls back to official', () async {
    final res = await executorsWith(
      snapshot,
    ).execute('getExchangeRate', {'from': 'USD', 'to': 'ARS', 'market': 'ccl'});
    expect(res['ok'], isTrue);
    expect(res['market'], 'official');
  });

  test('an old quote is flagged stale', () async {
    final res = await executorsWith([
      FxQuote(
        base: 'USD',
        quote: 'ARS',
        market: 'official',
        rate: 1505,
        source: 'dolarapi',
        asOf: DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 9))
            .toIso8601String(),
      ),
    ]).execute('getExchangeRate', {'from': 'USD', 'to': 'ARS'});
    expect(res['stale'], isTrue);
  });

  test('an empty cache is reported, never guessed around', () async {
    final res = await executorsWith(
      const [],
    ).execute('getExchangeRate', {'from': 'USD', 'to': 'ARS'});
    expect(res, {
      'ok': false,
      'error': 'Exchange rates are unavailable right now',
    });
  });

  test('a device with no cache at all behaves the same', () async {
    final res = await ToolExecutors(
      AppRepositories(db),
    ).execute('getExchangeRate', {'from': 'USD', 'to': 'ARS'});
    expect(res['ok'], isFalse);
    expect(res['error'], 'Exchange rates are unavailable right now');
  });

  test('an uncovered pair is refused rather than invented', () async {
    final res = await executorsWith(
      snapshot,
    ).execute('getExchangeRate', {'from': 'USD', 'to': 'JPY'});
    expect(res, {
      'ok': false,
      'error': 'No exchange rate available for USD→JPY',
    });
  });

  test('unknown and identical currency codes are rejected', () async {
    final tools = executorsWith(snapshot);
    expect(
      await tools.execute('getExchangeRate', {'from': 'XXX', 'to': 'ARS'}),
      {'ok': false, 'error': 'Unknown currency code: XXX'},
    );
    expect(
      await tools.execute('getExchangeRate', {'from': 'USD', 'to': 'USD'}),
      {'ok': false, 'error': 'from and to are the same currency'},
    );
    expect(await tools.execute('getExchangeRate', {}), {
      'ok': false,
      'error': 'from and to are required',
    });
  });
}
