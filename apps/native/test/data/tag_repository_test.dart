import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Tag domain logic moved verbatim from tags_view.dart: reparent backfill
// (plan invariant #9) and the two archive modes.
void main() {
  late AppDatabase db;
  late AppRepositories repos;
  late String accountId;
  late String categoryId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
    accountId = await repos.accounts.create(name: 'Cash', currency: 'ARS');
    categoryId = await repos.categories.create(name: 'Food');
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> expenseTagged(List<String> tagIds, {String name = 'e'}) =>
      repos.transactions.addExpense(
        accountId: accountId,
        categoryId: categoryId,
        name: name,
        amountCents: BigInt.from(100),
        currency: 'ARS',
        tagIds: tagIds,
      );

  group('reparent backfill', () {
    test('new parent backfills the ancestor chain onto transactions of the tag '
        'and its descendants, without duplicating joins', () async {
      final grandparent = await repos.tags.create(name: 'GP');
      final parent = await repos.tags.create(name: 'P', parentId: grandparent);
      final tag = await repos.tags.create(name: 'T');
      final child = await repos.tags.create(name: 'C', parentId: tag);

      final txnWithTag = await expenseTagged([tag]);
      final txnWithChild = await expenseTagged([child]);
      // Already has the parent join: must not be duplicated.
      final txnWithBoth = await expenseTagged([tag, parent]);

      await repos.tags.update(tag, parentId: Value(parent));

      expect((await repos.transactions.tagIdsOf(txnWithTag)).toSet(), {
        tag,
        parent,
        grandparent,
      });
      expect((await repos.transactions.tagIdsOf(txnWithChild)).toSet(), {
        child,
        parent,
        grandparent,
      });
      expect((await repos.transactions.tagIdsOf(txnWithBoth)).toSet(), {
        tag,
        parent,
        grandparent,
      });
    });

    test(
      'clearing the parent does NOT remove ancestor joins (asymmetric)',
      () async {
        final parent = await repos.tags.create(name: 'P');
        final tag = await repos.tags.create(name: 'T');
        final txn = await expenseTagged([tag]);

        await repos.tags.update(tag, parentId: Value(parent));
        expect((await repos.transactions.tagIdsOf(txn)).toSet(), {tag, parent});

        await repos.tags.update(tag, parentId: const Value(null));
        expect((await repos.transactions.tagIdsOf(txn)).toSet(), {
          tag,
          parent,
        }, reason: 'backfill is add-only by design');
        expect((await repos.tags.getById(tag))!.parentId, isNull);
      },
    );

    test('re-setting the same parent does not backfill again', () async {
      final parent = await repos.tags.create(name: 'P');
      final tag = await repos.tags.create(name: 'T', parentId: parent);
      final txn = await expenseTagged([tag]);

      // parentId present but unchanged → no backfill.
      await repos.tags.update(tag, parentId: Value(parent));
      expect((await repos.transactions.tagIdsOf(txn)), [tag]);
    });
  });

  group('archive modes', () {
    test('cascade archives + tombstones every descendant', () async {
      final root = await repos.tags.create(name: 'root');
      final child = await repos.tags.create(name: 'child', parentId: root);
      final grandchild = await repos.tags.create(
        name: 'grandchild',
        parentId: child,
      );
      final unrelated = await repos.tags.create(name: 'unrelated');

      await repos.tags.archive(root, mode: TagArchiveMode.cascade);

      for (final id in [root, child, grandchild]) {
        final tag = (await repos.tags.getById(id))!;
        expect(tag.archived, isTrue, reason: '$id should be archived');
      }
      expect((await repos.tags.getById(unrelated))!.archived, isFalse);

      final tombs = await (db.select(db.tombstones)).get();
      expect(tombs.map((t) => t.entityId).toSet(), {root, child, grandchild});
    });

    test('reparentChildren lifts direct children to the grandparent', () async {
      final grandparent = await repos.tags.create(name: 'gp');
      final middle = await repos.tags.create(
        name: 'mid',
        parentId: grandparent,
      );
      final child = await repos.tags.create(name: 'child', parentId: middle);

      await repos.tags.archive(middle, mode: TagArchiveMode.reparentChildren);

      expect((await repos.tags.getById(middle))!.archived, isTrue);
      final lifted = (await repos.tags.getById(child))!;
      expect(lifted.archived, isFalse);
      expect(lifted.parentId, grandparent);

      final tombs = await (db.select(db.tombstones)).get();
      expect(tombs.map((t) => t.entityId).toList(), [middle]);
    });

    test('reparentChildren with no grandparent makes children roots', () async {
      final root = await repos.tags.create(name: 'root');
      final child = await repos.tags.create(name: 'child', parentId: root);

      await repos.tags.archive(root, mode: TagArchiveMode.reparentChildren);

      expect((await repos.tags.getById(child))!.parentId, isNull);
    });
  });
}
