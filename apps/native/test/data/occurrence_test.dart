import 'package:app/data/data.dart';
import 'package:app/data/occurrence.dart';
import 'package:app/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The cutoff has to land on the same number as `occurrence.test.ts`: a
/// movement must fall on the same side of the boundary on the phone and on the
/// web, or the same account would report two different balances.
void main() {
  group('cutoff arithmetic', () {
    DateTime utc(String iso) => DateTime.parse(iso);

    test('is the end of the 20-minute block', () {
      expect(occurrenceBucketSeconds, 20 * 60);
      expect(
        pastCutoffMs(utc('2026-09-03T14:07:31.500Z')),
        BigInt.from(utc('2026-09-03T14:20:00.000Z').millisecondsSinceEpoch),
      );
      expect(
        pastCutoffMs(utc('2026-09-03T14:39:59.999Z')),
        BigInt.from(utc('2026-09-03T14:40:00.000Z').millisecondsSinceEpoch),
      );
    });

    test('rounds up, never down', () {
      // Load-bearing: the cutoff is an exclusive upper bound, so rounding down
      // would put a movement recorded *right now* above it and make the
      // expense the user just entered vanish from the activity list.
      final now = utc('2026-09-03T14:07:31.500Z');
      expect(
        pastCutoffMs(now) > BigInt.from(now.millisecondsSinceEpoch),
        isTrue,
      );
    });

    test('moves past a now that sits exactly on a boundary', () {
      expect(
        pastCutoffMs(utc('2026-09-03T14:20:00.000Z')),
        BigInt.from(utc('2026-09-03T14:40:00.000Z').millisecondsSinceEpoch),
      );
    });

    test('advances exactly once per block', () {
      final start = utc('2026-09-03T14:00:00.000Z').millisecondsSinceEpoch;
      final seen = <BigInt>{};
      for (var minute = 0; minute < 60; minute++) {
        seen.add(
          pastCutoffMs(
            DateTime.fromMillisecondsSinceEpoch(start + minute * 60000),
          ),
        );
      }
      expect(seen, hasLength(3));
    });
  });

  group('the cutoff is evaluated by SQL, not baked in', () {
    late AppDatabase db;
    late AppRepositories repos;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repos = AppRepositories(db);
    });
    tearDown(() => db.close());

    test('splits the same rows the arithmetic predicts', () async {
      final cashId = await repos.accounts.create(name: 'Cash', currency: 'ARS');
      final foodId = await repos.categories.create(name: 'Food');

      Future<void> add(String name, Duration offset) =>
          repos.transactions.addExpense(
            accountId: cashId,
            categoryId: foodId,
            name: name,
            amountCents: BigInt.from(100),
            currency: 'ARS',
            dateMs: BigInt.from(
              DateTime.now().add(offset).millisecondsSinceEpoch,
            ),
            timeStatus: TransactionTimeStatus.confirmed,
          );

      await add('an hour ago', const Duration(hours: -1));
      // Recording something "now" must read as already happened — this is the
      // case a rounded-down cutoff would have hidden.
      await add('now', Duration.zero);
      await add('tomorrow', const Duration(days: 1));

      final occurred = await repos.transactions.list(const TransactionFilter());
      expect(occurred.map((t) => t.name), containsAll(['an hour ago', 'now']));
      expect(occurred.map((t) => t.name), isNot(contains('tomorrow')));

      final upcoming = await repos.transactions.listUpcoming();
      expect(upcoming.map((t) => t.name), ['tomorrow']);
    });

    test('the balance stops at the cutoff', () async {
      final cashId = await repos.accounts.create(name: 'Cash', currency: 'ARS');
      final foodId = await repos.categories.create(name: 'Food');
      await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'Later',
        amountCents: BigInt.from(5000),
        currency: 'ARS',
        dateMs: BigInt.from(
          DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch,
        ),
        timeStatus: TransactionTimeStatus.confirmed,
      );

      // The money has not left yet, so the balance must not know about it.
      expect(await repos.accounts.getBalanceCents(cashId), BigInt.zero);
    });
  });
}
