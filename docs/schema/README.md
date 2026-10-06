# Native SQLite schema and migrations

`apps/native/lib/database.dart` is the source of truth for the native Drift
schema. `apps/native/drift_schemas/app_database/` stores the versioned
snapshots used to test it.

## Current schema

The complete current schema is `v6`. `v1` is the native SQLite baseline. Each later version added:

| Version | Change |
|---|---|
| `v2` | `transactions.time_status` |
| `v3` | `legal_acceptances` table (Terms/Privacy acceptance records — see `docs/legal/README.md`) |
| `v4` | `agent_memories` table (the agent's synced long-term memory); shipped with a `minSupportedVersion` bump to 0.3.0 |
| `v5` | `recurrences` table plus `transactions.recurrence_id` / `recurrence_index`; resets `sync_state.last_server_seq` to replay history |
| `v6` | nullable `accounts.position` / `categories.position` / `tags.position` (user-chosen list order, WAL-199; for tags, the order among siblings); resets `sync_state.last_server_seq` to replay history |

Supported upgrade paths are every `vN -> v6` for `N` from 1 to 5. The steps in `AppDatabase.migration` are cumulative and must stay that way: each is an independent `if (from < N)` block, never an early `return`, or a v1 database jumping straight to the current version would silently skip everything after the first step.

Historical development databases from before this baseline are not supported by
runtime cleanup helpers. Unsupported paths must fail explicitly instead of
guessing, inspecting columns dynamically, or silently dropping data.

Schema changes must be coordinated with the team before merging so every
developer and tester knows whether their local database can be migrated or must
be reset.

## Updating the schema

Every schema correction must bump `AppDatabase.schemaVersion`, implement the
upgrade path from the previous supported version, and regenerate Drift's
migration artifacts:

```bash
cd apps/native
dart run drift_dev make-migrations
dart run drift_dev schema generate --no-data-classes --no-companions \
  drift_schemas/app_database test/generated_migrations
flutter test test/database_migration_test.dart
```

Generated JSON and Dart files must not be edited by hand.

`make-migrations` reads `build.yaml`, exports the next schema snapshot, and
generates Drift migration utilities when a new upgrade step exists. The upgrade
implementation should use Drift's migration APIs first (`Migrator`,
`stepByStep`, generated schema helpers) and fall back to `customStatement` only
for SQL that Drift cannot express clearly.

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
