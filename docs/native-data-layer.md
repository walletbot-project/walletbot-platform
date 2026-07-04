# Native app data-access layer

How data is read and written in `apps/native`, and how to extend it without
breaking sync, multi-user support, or the voice agent.

## The one-paragraph version

All app-level data access goes through the repositories in `lib/data/`,
injected as a single `AppRepositories` bundle via Provider. Reads are Drift
streams consumed with `StreamBuilder` (reactive to local writes, agent writes,
and sync merges — no manual refresh anywhere). Writes go through repository
methods that enforce the sync contract. The sync engine (`lib/sync/`) is the
only other code allowed to touch Drift directly, deliberately — its merge
semantics are different and must stay separate.

## Layout

```
lib/shared/                 # pure helpers: money.dart, dates.dart, text.dart
lib/data/
  app_repositories.dart     # the bundle registered in Provider (one field per repo)
  data.dart                 # barrel — import this from screens/agent code
  entity_resolver.dart      # id-or-fuzzy-name resolution (agent tools)
  ids.dart                  # newUuid() — the only id scheme for local writes
  tombstones.dart           # writeTombstone() — the delete half of every soft delete
  models/                   # TransactionFilter, summaries, entity counts
  queries/                  # transaction_query.dart (THE filter→SQL builder), account_balance.dart
  repositories/             # repository_base.dart + one repository per entity
```

Provider wiring lives in `main.dart` inside the `ValueKey(account.id)`
`MultiProvider`, so the bundle is created and disposed together with the
per-user database. Repositories are stateless — never cache rows or hold
broadcast controllers in them; SQLite is the cache.

## The write contract (do not bend it)

The sync engine pushes rows where `dirty = true` and resolves conflicts by
last-writer-wins on `updatedAt`. Every repository write therefore:

1. sets `dirty: Value(true)` AND bumps `updatedAt` in the same statement;
2. soft-deletes only: `archived = true` **+** `writeTombstone(...)`, both
   inside one `db.transaction()` (joins in `transactionTags` are the one
   exception: hard-deleted, but still tombstoned per join);
3. never writes `dirty = false` — only the sync engine clears it (push ack);
4. uses the Drift table API (no `customStatement` writes — they bypass stream
   notifications and the sync trigger);
5. generates ids with `newUuid()`; `transactionTags` join ids are
   deterministic (`'<txnId>__<tagId>'`) so untag → retag round-trips converge.

`test/data/write_contract_test.dart` enforces most of this; extend it when you
add write methods.

## Reading data (screens)

```dart
final repos = context.read<AppRepositories>();   // read, not watch — stable per account

StreamBuilder<List<Transaction>>(
  stream: repos.transactions.watch(filter, limit: limit),
  builder: (context, snapshot) { ... },           // handle waiting/error/empty
)
```

- Build the stream in `build()` from current widget state (filter, limit) —
  Drift query streams are cheap to (re)subscribe.
- Transaction filtering always goes through `TransactionFilter` +
  `repos.transactions.watch/list`. Never hand-build a transactions query in a
  widget — extend the filter model and `buildTransactionQuery` instead, so the
  UI and the agent stay in sync.
- Routes pushed on the root navigator (dialogs/sheets/screens via
  `Navigator.push`) sit **above** the account-scoped providers: capture
  `AppRepositories` in the pushing context and hand it down explicitly (see
  `accounts.dart`), and pop the route on account switch when it can write
  (see `_PopOnAccountSwitch` in `main.dart`).

## Writing data

Call the repository method; never touch `db` from widgets or tools:

```dart
await repos.transactions.addExpense(
  accountId: acc.id, categoryId: cat.id,
  name: 'Sandwich', amountCents: BigInt.from(1500), currency: acc.currency,
);
```

Partial updates use drift `Value<T>`: `Value(x)` sets, `Value(null)` clears a
nullable field, `Value.absent()` (the default) keeps it. This distinction is
load-bearing for the agent (e.g. "clear the tag's parent" vs "don't touch it").

## Recipes

**New screen that shows data** — `context.read<AppRepositories>()` + a
`StreamBuilder` on an existing `watch*` method. Done.

**New read** — add a `watch*` (stream) method to the entity's repository;
add a `Future` variant only if the agent needs it. For `customSelect`, declare
every table the SQL touches in `readsFrom:` — that set is what keeps the
stream live when sync merges land.

**New write** — add a repository method following the contract above; wrap
multi-row work in `db.transaction()`; add a write-contract test (dirty set,
updatedAt bumped, tombstone written if it deletes).

**New agent tool** — add a case in `ToolExecutors.execute` that resolves names
via `repos.resolver`, calls repository methods, and maps the result to the
`{'ok': bool, ...}` envelope (amounts as `cents / 100` doubles via
`centsToDouble`). No SQL, no dirty-flag knowledge in the tool layer. Lock the
envelope in `test/voice/tool_executors_test.dart`.

**New table** — define it in `database.dart` with the standard columns
(`id`, `createdAt`, `updatedAt`, `archived`, `dirty`), run
`dart run build_runner build --delete-conflicting-outputs`, create a
repository for it, add a field to `AppRepositories`, and extend the sync
engine's table list + merge logic (that part is sync work — see below).

## What the data layer must NOT do

- **Don't route sync through repositories.** `sync_merge.dart` writes pulled
  rows with `dirty = false` on purpose; using the user-write path would mark
  every pulled row dirty and bounce changes between devices forever.
  `sync_recompute.dart` has its own correction semantics. Leave `lib/sync/`
  writing Drift directly.
- **Don't call `notifyLocalWrite()` or touch the sync engine.** The engine
  watches `db.tableUpdates()`; committing a tracked write is the whole
  contract.
- **Don't construct `AppDatabase` anywhere but `main.dart`** (`forUser`) and
  tests (`forTesting`). A second instance has its own stream/update tracking —
  writes through it are invisible to the UI and to sync.
- **Don't keep balance math in two places.** `queries/account_balance.dart`
  must stay arithmetically identical to the replay in `sync_recompute.dart`;
  `test/sync/balance_recompute_test.dart` is the parity guard.

## Maintenance

- Per change: `flutter analyze && flutter test` in `apps/native` (CI runs both
  on PRs via `.github/workflows/native.yml`).
- Review gate — this grep must return nothing outside `lib/data/` and
  `lib/sync/`:

  ```sh
  grep -rn "db\.into(\|db\.update(\|db\.delete(\|\.select(db\.\|db\.customSelect" lib \
    | grep -v "^lib/data/" | grep -v "^lib/sync/"
  ```

  (`import 'package:drift/drift.dart' show Value;` outside those dirs is fine —
  `Value` is the partial-update API surface, not database access.)
- Schema changes: `dart run build_runner build --delete-conflicting-outputs`,
  and keep the Convex dev server running so backend types regenerate.
- Before touching sync or auth, read `LESSONS.md` at the repo root.
