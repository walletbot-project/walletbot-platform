import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Business rule (WAL-148): an account's name+currency must be unique
// (trim + case-insensitive) among a user's active accounts. The same name
// is allowed across different currencies, and archiving an account frees up
// its name+currency combo for reuse.
void main() {
  late AppDatabase db;
  late AppRepositories repos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('create', () {
    test('rejects the same name+currency, trim + case-insensitive', () async {
      await repos.accounts.create(name: 'Efectivo', currency: 'ARS');

      expect(
        () => repos.accounts.create(name: ' efectivo ', currency: 'ARS'),
        throwsA(isA<DuplicateAccountException>()),
      );
    });

    test('allows the same name with a different currency', () async {
      await repos.accounts.create(name: 'Efectivo', currency: 'ARS');

      final id = await repos.accounts.create(name: 'Efectivo', currency: 'USD');

      expect(id, isNotEmpty);
    });

    test('allows reusing the name+currency of an archived account', () async {
      final original = await repos.accounts.create(
        name: 'Efectivo',
        currency: 'ARS',
      );
      await repos.accounts.archive(original);

      final id = await repos.accounts.create(name: 'Efectivo', currency: 'ARS');

      expect(id, isNotEmpty);
    });
  });

  group('update', () {
    test(
      'rejects renaming into another active account\'s name+currency',
      () async {
        await repos.accounts.create(name: 'Efectivo', currency: 'ARS');
        final target = await repos.accounts.create(
          name: 'Banco',
          currency: 'ARS',
        );

        expect(
          () => repos.accounts.update(target, name: const Value('efectivo')),
          throwsA(isA<DuplicateAccountException>()),
        );
      },
    );

    test('allows renaming an account to its own current name', () async {
      final id = await repos.accounts.create(name: 'Efectivo', currency: 'ARS');

      await repos.accounts.update(id, name: const Value('Efectivo'));

      expect((await repos.accounts.getById(id))!.name, 'Efectivo');
    });

    test('leaves other fields untouched when name is absent', () async {
      await repos.accounts.create(name: 'Efectivo', currency: 'ARS');
      final target = await repos.accounts.create(
        name: 'Banco',
        currency: 'ARS',
      );

      await repos.accounts.update(target, color: const Value('#FF0000'));

      expect((await repos.accounts.getById(target))!.color, '#FF0000');
    });
  });
}
