import 'package:app/database.dart';
import 'package:app/sync/sync_merge.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../generated_migrations/schema.dart';

void main() {
  for (final table in ['accounts', 'categories', 'tags']) {
    test(
      'v5 upgrade hydrates $table position while retaining a newer offline rename',
      () async {
        final verifier = SchemaVerifier(GeneratedHelper());
        final schema = await verifier.schemaAt(5);
        addTearDown(schema.close);
        schema.rawDatabase.execute(
          "INSERT INTO $table (id, name, ${table == 'accounts' ? 'currency, ' : ''}created_at, updated_at, dirty) "
          "VALUES ('a', 'Offline rename', ${table == 'accounts' ? "'ARS', " : ''}1, 200, 1)",
        );
        schema.rawDatabase.execute(
          "INSERT INTO sync_state (id, last_server_seq) VALUES ('singleton', 5)",
        );
        final db = AppDatabase.forTesting(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, 6);
        await PullPageMerger(db).applyPage(
          rows: [
            {
              'tableName': table,
              'row': {
                'id': 'a',
                'name': 'Before rename',
                if (table == 'accounts') 'currency': 'ARS',
                'color': '#000000',
                'icon': 'wallet',
                'createdAt': BigInt.one,
                'updatedAt': BigInt.from(100),
                'isArchived': false,
                'position': 0.0,
              },
            },
          ],
          tombstones: [],
        );
        final row = await db
            .customSelect(
              'SELECT name, dirty, updated_at, position FROM $table',
            )
            .getSingle();
        expect(row.read<String>('name'), 'Offline rename');
        expect(row.read<int>('dirty'), 1);
        expect(row.read<int>('updated_at'), 200);
        expect(
          row.readNullable<int>('position'),
          0,
          reason:
              'Upgrade replay must hydrate the order chosen on web without losing the newer offline rename',
        );
      },
    );
  }

  for (final table in ['accounts', 'categories', 'tags']) {
    test('a newer local $table reorder wins over the pulled position', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customStatement(
        "INSERT INTO $table (id, name, ${table == 'accounts' ? 'currency, ' : ''}created_at, updated_at, dirty, position) "
        "VALUES ('a', 'Offline edit', ${table == 'accounts' ? "'ARS', " : ''}1, 200, 1, 2)",
      );
      await PullPageMerger(db).applyPage(
        rows: [
          {
            'tableName': table,
            'row': {
              'id': 'a',
              'name': 'Before edit',
              if (table == 'accounts') 'currency': 'ARS',
              'createdAt': BigInt.one,
              'updatedAt': BigInt.from(100),
              'position': 0.0,
            },
          },
        ],
        tombstones: [],
      );
      final row = await db
          .customSelect('SELECT name, dirty, updated_at, position FROM $table')
          .getSingle();
      expect(row.read<String>('name'), 'Offline edit');
      expect(row.read<int>('dirty'), 1);
      expect(row.read<int>('updated_at'), 200);
      expect(row.read<int>('position'), 2);
    });
  }

  test(
    'a newer local tag re-parent never inherits its old sibling position',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customStatement(
        "INSERT INTO tags (id, name, parent_id, created_at, updated_at, dirty) "
        "VALUES ('a', 'Moved tag', 'new-parent', 1, 200, 1)",
      );
      await PullPageMerger(db).applyPage(
        rows: [
          {
            'tableName': 'tags',
            'row': {
              'id': 'a',
              'name': 'Before move',
              'parentId': 'old-parent',
              'createdAt': BigInt.one,
              'updatedAt': BigInt.from(100),
              'position': 0.0,
            },
          },
        ],
        tombstones: [],
      );
      final tag = await db.select(db.tags).getSingle();
      expect(tag.name, 'Moved tag');
      expect(tag.parentId, 'new-parent');
      expect(tag.position, isNull);
      expect(tag.dirty, isTrue);
      expect(tag.updatedAt, BigInt.from(200));
    },
  );
}
