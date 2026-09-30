import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/sync/sync_merge.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// User-chosen order for accounts and categories (v6). Positioned rows come
// first by `position`; the rest follow by creation, which is where a new item
// has always appeared. Mirrors `compareByPosition` in @wallet-bot/shared.
void main() {
  late AppDatabase db;
  late AppRepositories repos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
  });

  tearDown(() async => db.close());

  // Rows created in one test share a millisecond; pin distinct creation
  // times so the creation-order fallback is deterministic.
  Future<void> stagger(String table, List<String> ids) async {
    for (var i = 0; i < ids.length; i++) {
      await db.customStatement(
        'UPDATE $table SET created_at = ? WHERE id = ?',
        [i + 1, ids[i]],
      );
    }
  }

  Future<void> markClean() async {
    await db.customStatement('UPDATE accounts SET dirty = 0');
    await db.customStatement('UPDATE categories SET dirty = 0');
  }

  test('accounts keep creation order until reordered', () async {
    final a = await repos.accounts.create(name: 'A', currency: 'ARS');
    final b = await repos.accounts.create(name: 'B', currency: 'ARS');
    final c = await repos.accounts.create(name: 'C', currency: 'ARS');
    await stagger('accounts', [a, b, c]);

    expect((await repos.accounts.listActive()).map((x) => x.id), [a, b, c]);

    await repos.accounts.reorder([c, a, b]);
    expect((await repos.accounts.listActive()).map((x) => x.id), [c, a, b]);
    expect((await repos.accounts.watchActive().first).map((x) => x.id), [
      c,
      a,
      b,
    ]);
  });

  test('a new account lands after the reordered ones', () async {
    final a = await repos.accounts.create(name: 'A', currency: 'ARS');
    final b = await repos.accounts.create(name: 'B', currency: 'ARS');
    await repos.accounts.reorder([b, a]);

    final fresh = await repos.accounts.create(name: 'Nueva', currency: 'ARS');
    await stagger('accounts', [a, b, fresh]);

    expect((await repos.accounts.listActive()).map((x) => x.id), [b, a, fresh]);
  });

  test('reorder only re-dirties the rows that moved', () async {
    final a = await repos.accounts.create(name: 'A', currency: 'ARS');
    final b = await repos.accounts.create(name: 'B', currency: 'ARS');
    final c = await repos.accounts.create(name: 'C', currency: 'ARS');
    await repos.accounts.reorder([a, b, c]);
    await markClean();

    await repos.accounts.reorder([a, c, b]);

    final dirty = {
      for (final row in await repos.accounts.listAll()) row.id: row.dirty,
    };
    expect(dirty, {a: false, b: true, c: true});
  });

  test('categories reorder, including the counted list', () async {
    final food = await repos.categories.create(name: 'Comida');
    final rent = await repos.categories.create(name: 'Alquiler');
    final fun = await repos.categories.create(name: 'Ocio');
    await stagger('categories', [food, rent, fun]);

    // Creation order, not name order.
    expect(
      (await repos.categories.watchWithCounts().first).map(
        (e) => e.category.id,
      ),
      [food, rent, fun],
    );

    await repos.categories.reorder([fun, food, rent]);

    expect((await repos.categories.listActive()).map((x) => x.id), [
      fun,
      food,
      rent,
    ]);
    final counted = await repos.categories.watchWithCounts().first;
    expect(counted.map((e) => e.category.id), [fun, food, rent]);
    expect(counted.map((e) => e.category.position), [0, 1, 2]);
  });

  test('pulled rows carry position, and rows without one stay NULL', () async {
    final merger = PullPageMerger(db);
    Map<String, Object?> account(String id, {Object? position}) => {
      'id': id,
      'name': id,
      'currency': 'ARS',
      'color': '#000000',
      'icon': 'wallet',
      'isArchived': false,
      'createdAt': BigInt.one,
      'updatedAt': BigInt.from(10),
      'position': ?position,
    };
    await merger.applyPage(
      rows: [
        // Convex numbers arrive as doubles.
        {'tableName': 'accounts', 'row': account('x', position: 1.0)},
        {'tableName': 'accounts', 'row': account('y', position: 0.0)},
        {'tableName': 'accounts', 'row': account('z')},
      ],
      tombstones: [],
    );

    final rows = await repos.accounts.listActive();
    expect(rows.map((r) => r.id), ['y', 'x', 'z']);
    expect(rows.map((r) => r.position), [0, 1, null]);
  });

  group('tags', () {
    late Map<String, String> ids;

    setUp(() async {
      final hogar = await repos.tags.create(name: 'Hogar');
      ids = {
        'Hogar': hogar,
        'Luz': await repos.tags.create(name: 'Luz', parentId: hogar),
        'Agua': await repos.tags.create(name: 'Agua', parentId: hogar),
        'Auto': await repos.tags.create(name: 'Auto'),
      };
    });

    Future<Map<String, Tag>> byName() async => {
      for (final t in await repos.tags.listAll()) t.name: t,
    };

    test('reorder refuses ids from another level and writes nothing', () async {
      await expectLater(
        repos.tags.reorder(null, [ids['Luz']!, ids['Auto']!]),
        throwsArgumentError,
      );
      final tags = await byName();
      expect(tags.values.every((t) => t.position == null), isTrue);
    });

    test(
      'unpositioned tags stay alphabetical after the reordered ones',
      () async {
        await repos.tags.reorder(ids['Hogar'], [ids['Luz']!]);
        final nuevo = await repos.tags.create(
          name: 'Gas',
          parentId: ids['Hogar'],
        );
        final rows = await repos.tags.watchWithCounts().first;
        expect(
          rows
              .where((r) => r.tag.parentId == ids['Hogar'])
              .map((r) => r.tag.id),
          [ids['Luz'], ids['Agua'], nuevo],
        );
      },
    );

    test('changing parent clears the position; renaming keeps it', () async {
      await repos.tags.reorder(null, [ids['Auto']!, ids['Hogar']!]);
      await repos.tags.update(ids['Auto']!, parentId: Value(ids['Hogar']));
      await repos.tags.update(ids['Hogar']!, name: const Value('Casa'));
      final tags = await byName();
      expect(tags['Auto']!.position, isNull);
      expect(tags['Casa']!.position, 1);
    });

    test('children re-parented by an archive lose their position', () async {
      await repos.tags.reorder(ids['Hogar'], [ids['Luz']!, ids['Agua']!]);
      await repos.tags.archive(
        ids['Hogar']!,
        mode: TagArchiveMode.reparentChildren,
      );
      final tags = await byName();
      expect(tags['Luz']!.parentId, isNull);
      expect(tags['Luz']!.position, isNull);
      expect(tags['Agua']!.position, isNull);
    });

    test('pulled tags carry their position', () async {
      await PullPageMerger(db).applyPage(
        rows: [
          {
            'tableName': 'tags',
            'row': {
              'id': 'remote',
              'name': 'Remoto',
              'color': '#000000',
              'position': 0.0,
              'isArchived': false,
              'createdAt': BigInt.one,
              'updatedAt': BigInt.from(10),
            },
          },
        ],
        tombstones: [],
      );
      expect((await repos.tags.getById('remote'))!.position, 0);
    });
  });
}
