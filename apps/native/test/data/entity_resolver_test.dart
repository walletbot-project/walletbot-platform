import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Resolver semantics preserved from tool_executors (plan invariant: B1):
// id-exact first, then normalized unique name match among active rows;
// multiple matches are Ambiguous, never a guess.
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

  test('resolves by exact id', () async {
    final id = await repos.accounts.create(name: 'Cash', currency: 'ARS');
    final result = await repos.resolver.account(id);
    expect(result, isA<Resolved<Account>>());
    expect((result as Resolved<Account>).value.id, id);
  });

  test('resolves by normalized unique name', () async {
    final id = await repos.accounts.create(
      name: 'Banco Nación',
      currency: 'ARS',
    );
    final result = await repos.resolver.account('  banco nación ');
    expect(result, isA<Resolved<Account>>());
    expect((result as Resolved<Account>).value.id, id);
  });

  test('duplicate names are ambiguous, with candidates', () async {
    await repos.accounts.create(name: 'Cash', currency: 'ARS');
    await repos.accounts.create(name: 'cash', currency: 'USD');
    final result = await repos.resolver.account('CASH');
    expect(result, isA<Ambiguous<Account>>());
    expect((result as Ambiguous<Account>).candidates, hasLength(2));
  });

  test('archived entities do not resolve by name', () async {
    final id = await repos.categories.create(name: 'Food');
    await repos.categories.archive(id);
    final result = await repos.resolver.category('food');
    expect(result, isA<NotFound<Category>>());
  });

  test('archived entities still resolve by id', () async {
    final id = await repos.tags.create(name: 'Old');
    await repos.tags.archive(id, mode: TagArchiveMode.reparentChildren);
    final result = await repos.resolver.tag(id);
    expect(result, isA<Resolved<Tag>>());
  });
}
