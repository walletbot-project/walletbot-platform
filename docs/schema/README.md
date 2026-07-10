# Native SQLite schema and migrations

`apps/native/lib/database.dart` is the source of truth for the native Drift
schema. `apps/native/drift_schemas/` stores the versioned snapshots used to
test it.

## Current baseline

The complete current schema is `v1`. This is an intentional pre-release reset:
existing development installations are not supported and must clear app data
or reinstall. No public release may rely on an older local schema.

The v1 snapshot becomes immutable when the first public native build ships.
After that point, deleting local data is not a migration strategy.

## Before the first public release

Schema corrections may remain in `v1`, but every correction must regenerate
the snapshot and test helper:

```bash
cd apps/native
dart run drift_dev schema dump lib/database.dart drift_schemas
dart run drift_dev schema generate --no-data-classes --no-companions \
  drift_schemas test/generated_migrations
flutter test test/database_migration_test.dart
```

Generated JSON and Dart files must not be edited by hand.

## After the first public release

For every schema change:

1. Increment `AppDatabase.schemaVersion` by one.
2. Keep every existing snapshot unchanged.
3. Implement the explicit `onUpgrade` step from the previous version.
4. Preserve existing rows and defaults; never silently drop user data.
5. Export the new snapshot and regenerate the test helper with the commands
   above.
6. Add both tests:
   - `SchemaVerifier.migrateAndValidate` for the exact resulting schema,
     including indexes and constraints.
   - A data-integrity test that starts at the prior snapshot, inserts realistic
     rows, migrates, and verifies their values afterward.
7. Run the full native checks:

```bash
flutter analyze
flutter test
```

If multiple released versions can upgrade directly to the new build, test each
supported starting version. Unsupported paths must fail explicitly.

## Review rules

- A table or column edit without a version bump is invalid after publication.
- A version bump without a snapshot, upgrade path, and tests is incomplete.
- `onCreate` must always create the latest schema for fresh installs.
- Downgrades are unsupported; never try to infer or partially apply one.
- Keep migration code local to `AppDatabase`; repositories and sync code should
  only see the final current schema.
