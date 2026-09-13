# Native backward compatibility — PR #263

Validated on 2026-09-13 against the development deployment
`proficient-finch-671`. Production was not deployed.

## Supported rollout

- The minimum native version stays at **0.3.0**. Config responses for 0.3.0,
  0.3.2 and 0.4.0 all returned `supported: true`, `forceUpdate: false`.
- 0.3.x receives occurred installments as ordinary movements. Future movements
  and recurrence rules stay on the server until that client can use them.
- Older writes preserve series metadata and affect only the selected movement.
- v4→v5 replays sync history without clearing local data or pending edits.
- Existing web calls may omit `asOfMs`; their fallback clock is reactive.

## Physical device

Pixel 8 Pro, Android 17. A separate package, `live.walletbot.app.compat263`,
used an isolated QA identity. The first build used the native 0.3.2 source
from `main`, with its original v4 database, sync engine, merger, serializer,
and balance calculation. A small test entry point exercised those components;
this was not a manual review of the stock app's screens.

1. Seeded three installments on the server: one occurred, one due at 11:40,
   and one a month later. The legacy client received **one** transaction and
   calculated **-10000 cents**.
2. Disconnected its sync transport, changed the transaction locally to
   **12000 cents**, then reconnected. Sync succeeded. An independent backend
   read confirmed the edited amount and the unchanged recurrence ID/index.
3. Left the legacy client running. At **11:40:19 ART**, the next installment
   arrived through the server's publication job and counter subscription.
   The client showed **two** transactions and **-22000 cents**, without an
   app restart, reload or upgrade.
4. Installed the 0.4.0 test build over that same package and database.
   Device logs confirmed `versionBefore=4 versionNow=5 hadUpgrade=true` and
   the reset sync cursor. Replay loaded **three** transactions and **one**
   rule. The earlier edit remained **12000 cents**, its series link was
   populated, and the occurred balance stayed **-22000 cents**.

The temporary package and isolated QA financial data were removed afterward.
The user's normal Wallet Bot installation was not replaced. Device language,
theme and network settings were not changed.

## Automated validation

- Backend: **98 tests passed**, including 10 compatibility integration tests
  and the native argument/skill version gates.
- Shared: **153 tests passed**.
- Native migration and sync suites: **25 tests passed**, including pending
  offline-edit hydration and archived series-template recovery.
- Workspace TypeScript checks passed. Focused Dart analysis and formatting
  checks passed.
- The development backfill completed successfully over **1186** inspected
  transactions; only future rows needing the server publication queue change.

Integration cases include hidden-only pagination, due publication and tag
rehydration, rescheduling, deletion, legacy push acknowledgement, migration
idempotence, old web argument shapes, and preservation of business timestamps
so publication does not overwrite newer offline edits.

## Review after merging main (2026-09-13)

Main was merged at `e0dfac7`. The native version is now `0.4.0+9` and the
minimum supported version remains `0.3.0`. The merge brought in the WhatsApp
agent, which required integration with the recurrence contract:

- WhatsApp transaction writes now use the shared aggregate helpers, maintaining
  the legacy publication queue and republishing tags after date edits.
- Balances, adjustments, activity and summaries apply the occurrence cutoff.
- The WhatsApp executor does not implement series operations. Its declarations
  omit recurrence/scope arguments, its skill index omits the recurrence guide,
  and execution rejects unsupported series arguments before writing.

Workspace typechecks, web lint, 684 native tests, 153 shared tests and 9 web
tests passed. Backend: **118 passed, 1 failed**. The remaining failure is a
new regression test exposing an existing publication defect, not a passing
compatibility verdict:

**Approval blocker:** `occurrences/internal.ts:publishDue` calls
`republishTransactionTags` for every due transaction. That helper calls native
Convex `.paginate()`, which may run only once per function execution. With two
queued transactions due together, the second call throws and rolls back the
whole publication batch, including its sync-counter changes. Old native
clients can therefore stop receiving due movements. Both calls already exist
in `cb39ea7`, before the merge. This issue was reported without changing the
publication implementation, in accordance with the requested merge-only scope.

Other existing findings remain outside the merge fixes:

- Native recurrence end dates are stored at midnight while occurrences can
  retain a later time. January 31 at noon through May 31 produces four monthly
  occurrences instead of five. Reproduced directly with the Dart calendar code.
- Native custom-day input permits visible `0`/`00` while retaining the last
  valid interval internally, so the displayed interval can differ from the
  saved one.
- Web amount-only edits with “this and future” reconstruct the date to minute
  precision. Existing seconds/milliseconds trigger a series split; the prior
  QA reproduced an extended monthly series shrinking from 96 to 48. The
  responsible date comparison and split path are unchanged.
