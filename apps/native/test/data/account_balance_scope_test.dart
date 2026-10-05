import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Balance card's scope: `watchBalanceForCurrency` sums every active
/// account in a currency, narrowed to `accountIds` when that list is not empty.
///
/// Empty must keep meaning "the whole currency" — that is what every card
/// written before account scoping stores, and reading it as an empty selection
/// would silently show zero on dashboards that used to work.
void main() {
  late AppDatabase db;
  late AppRepositories repos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
  });

  tearDown(() => db.close());

  Future<BigInt> balance(
    String currency, {
    List<String> accountIds = const [],
  }) => repos.accounts
      .watchBalanceForCurrency(currency, accountIds: accountIds)
      .first;

  /// An account holding [cents], via the initial-balance adjustment.
  Future<String> accountWith(String name, String currency, int cents) =>
      repos.accounts.create(
        name: name,
        currency: currency,
        initialBalanceCents: BigInt.from(cents),
      );

  test('an empty scope is every account in the currency', () async {
    await accountWith('Efectivo', 'ARS', 10000);
    await accountWith('Banco', 'ARS', 25000);
    await accountWith('Dólares', 'USD', 5000);

    expect(await balance('ARS'), BigInt.from(35000));
  });

  test('a scope narrows the sum to the chosen accounts', () async {
    final cash = await accountWith('Efectivo', 'ARS', 10000);
    await accountWith('Banco', 'ARS', 25000);

    expect(await balance('ARS', accountIds: [cash]), BigInt.from(10000));
  });

  test('several chosen accounts add up', () async {
    final cash = await accountWith('Efectivo', 'ARS', 10000);
    final bank = await accountWith('Banco', 'ARS', 25000);
    await accountWith('Ahorros', 'ARS', 999);

    expect(await balance('ARS', accountIds: [cash, bank]), BigInt.from(35000));
  });

  test('an id from another currency is ignored, never cross-summed', () async {
    final cash = await accountWith('Efectivo', 'ARS', 10000);
    final dollars = await accountWith('Dólares', 'USD', 5000);

    expect(
      await balance('ARS', accountIds: [cash, dollars]),
      BigInt.from(10000),
    );
  });

  test('an archived account drops out of the scope', () async {
    final cash = await accountWith('Efectivo', 'ARS', 10000);
    final bank = await accountWith('Banco', 'ARS', 25000);
    await repos.accounts.archive(bank);

    expect(await balance('ARS', accountIds: [cash, bank]), BigInt.from(10000));
  });

  test('a scope of only stale ids sums to zero, not to the currency', () async {
    await accountWith('Efectivo', 'ARS', 10000);

    expect(await balance('ARS', accountIds: ['gone']), BigInt.zero);
  });

  test('a transfer moves value between scoped accounts', () async {
    final cash = await accountWith('Efectivo', 'ARS', 10000);
    final bank = await accountWith('Banco', 'ARS', 0);
    // Dated just after the accounts opened: a movement at the very same
    // instant as an initial balance is ordered before it, so the declaration
    // would absorb the transfer.
    final opened = await (db.select(
      db.transactions,
    )..where((t) => t.type.equals('balance_adjustment'))).get();
    final afterOpening =
        opened.map((t) => t.date).reduce((a, b) => a > b ? a : b) + BigInt.one;
    await repos.transactions.addTransfer(
      fromAccountId: cash,
      toAccountId: bank,
      name: 'Retiro',
      amountCents: BigInt.from(4000),
      currency: 'ARS',
      toAmountCents: BigInt.from(4000),
      toCurrency: 'ARS',
      dateMs: afterOpening,
    );

    expect(await balance('ARS', accountIds: [cash]), BigInt.from(6000));
    expect(await balance('ARS', accountIds: [bank]), BigInt.from(4000));
    // The pair together is unchanged: a transfer never creates or destroys.
    expect(await balance('ARS'), BigInt.from(10000));
  });
}
