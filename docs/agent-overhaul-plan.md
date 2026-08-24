# Gaston agent overhaul — plan

Status: agreed direction, pending team sign-off on the schema v4 bump in Phase 6.
Scope: the Gemini Live agent ("Gaston", branded "Gasti") on native and web — tools, prompts,
context, memory, settings, skills, and the web reconnection bug.

## 1. Current state (summary)

- The agent is a Gemini Live voice/text session (`gemini-3.1-flash-live-preview`). Convex's
  only agent responsibility is minting a constrained ephemeral token
  (`packages/backend/convex/live/createToken.ts`) that bakes in the single system prompt and
  the 38 tool declarations from `packages/shared/src/tools/`. Both clients open the Google
  WebSocket directly and execute every tool locally — web against the Convex v1 API
  (`apps/web/src/lib/agent-tools/executors.ts`), native against Drift
  (`apps/native/lib/voice/tool_executors.dart`).
- `createLiveToken()` takes no arguments: the token is byte-identical for every user. No user
  name, accounts, categories, tags, transactions, memories, locale, platform, or timezone
  reach the prompt. The only dynamic line is "Today is …" computed on the Convex server clock
  (UTC, en-US) — wrong date for an ART user at night.
- Web loses the conversation on every disconnect: no reconnect logic (`use-voice.ts` onclose
  ends the session), typed-while-offline messages are dropped, the transcript is actively
  wiped (`setMessages([])` in `add.tsx:660` and `use-voice.ts:1008`), and the backend has no
  query that reads `voiceSessionEvents` back. Native fixed the same class of bug on
  2026-08-21 by re-seeding the transcript from its durable log on every connect
  (`buildConversationSeed`, `apps/native/lib/voice/voice_event.dart:166`); web has no
  equivalent. Tracked as item 1.5 in `docs/web-parity-backlog.md`.
- No memory subsystem, no settings tools, no skills. Language and theme are device-scoped
  (localStorage / SharedPreferences) and unreachable from tool executors on both platforms.

### Known defects (fixed by this plan regardless of anything else)

| # | Defect | Where |
|---|---|---|
| D1 | 9 dashboard tool descriptions say "native home dashboard" — web implements them all | `packages/shared/src/tools/index.ts:63-81` |
| D2 | `includeArchived` ignored by web for categories and tags (always `listActive`) | `apps/web/src/lib/agent-tools/executors.ts:120-134, 182-193` |
| D3 | `addTransfer` schema says `categoryIdOrName` optional; web executor hard-rejects it missing | `definitions.ts:244` vs `executors.ts:383-385` |
| D4 | Model + voice constants duplicated with no shared source (`createToken.ts:6,19` vs `gemini_voice_expense_command.dart:252-253`) — a backend bump silently desyncs native's setup frame | both files |
| D5 | Summaries walk `listPaginated` client-side (50 pages × 200 rows cap) — `TODO(aggregates)` | `executors.ts:559-647` |
| D6 | `tagList` arg description contains a leftover rhetorical Q&A ("Created on the fly if names are unknown? No — must exist.") | `definitions.ts:48-52` |
| D7 | Native executor coverage is convention-only (Dart switch); web is compile-enforced | `tool_executors.dart:31-115` |
| D8 | "Today is …" uses Convex server clock in en-US, not the user's timezone/locale | `createToken.ts:78-89` |
| D9 | Web history outbox has no unload flush (1 s debounce; closing the tab loses the tail) | `apps/web/src/lib/voice-history.ts` |
| D10 | Web marks a dropped session `ended` where native marks `suspended` | `voice-history.ts:75-82` |
| D11 | `docs/voice-session-lifecycle.md:16-17` still documents the abandoned resume-handle behaviour | docs |

## 2. Agreed design decisions

1. **User context travels in the mint request, not from the Convex DB.** Each client builds
   the context payload from its own source of truth — native from Drift (always fresh, even
   when sync lags), web from its Convex queries — and sends it as an argument to
   `requestLiveToken` alongside `platform`, `appVersion`, `locale`, `timezone`.
   `createLiveToken` does no DB reads: it validates the payload, enforces length limits to
   prevent abuse (per-list caps plus a hard cap on the serialized block, proposed 32 KB,
   truncate-with-marker beyond it), and interpolates it into the system prompt.
2. **Agent memory is a synced entity** (new `agentMemories` table in the sync protocol),
   which is a coordinated bump: backend `minSupportedVersion` + native Drift `schemaVersion`
   v3 → v4 in the same change, with data-preserving `onUpgrade`, Drift artifacts, and
   migration tests per `docs/schema/README.md`. Requires team agreement before Phase 6
   starts. The agent is explicitly allowed and instructed to **consolidate** its own
   memories — merge duplicates and rewrite stale entries via `updateMemory`, delete obsolete
   ones via `forgetMemory` — not only append.
3. **Web history fix targets parity with native** (reconnect + reseed; survives socket drops
   and navigation, not page reload). Reload survival is explicitly out of scope for now.
4. **Skills live in `packages/shared`** as bundled constants; the index goes in the system
   prompt; `readSkill` is a normal shared tool executed client-side (works offline, parity
   compile-enforced). Con accepted: updating a skill needs an app release on native.
5. **Full tool restructure is allowed** — renames, merges, and removals, not just fixes.
6. **Agent-changeable settings:** language (this device), theme (this device), default
   currency (account-wide). The voice-reply preference stays hardcoded for now.
7. **No feature flag.** The overhauled agent replaces the current one outright once each
   phase merges. The only gating is **compatibility**: the mint declares a new tool only to
   clients whose `platform` + `appVersion` can execute it (§7) — that is versioning, not an
   experiment switch.
8. Plan doc (this file) lives in `docs/`, English.

## 3. Target tool surface (38 → 39)

Names/schemas in `packages/shared/src/tools/definitions.ts` + `index.ts`; executors in
`apps/web/src/lib/agent-tools/executors.ts` and `apps/native/lib/voice/tool_executors.dart`.
Every description gets rewritten (platform-neutral, states defaults, states the error
contract). The uniform envelope stays `{ ok: true, ... } | { ok: false, error, candidates? }`.

### Removed (3)

| Tool | Why |
|---|---|
| `getRecentTransactions` | Absorbed by `listTransactions` (all args become optional; default `limit` 10 when no filters given). |
| `tagTransaction`, `untagTransaction` | Absorbed by `updateTransaction` via `addTagIdsOrNames` / `removeTagIdsOrNames`. |

Removal is safe versioning-wise: the declared tool set comes from the minted token, so old
clients simply never see calls to tools they'd lack — but see §7 for the reverse problem
(new tools on old clients).

### Merged (2 → 1)

`summarizeByCategory` + `summarizeByAccount` → **`summarizeTransactions`**
`{ groupBy: 'category' | 'account', dateFrom, dateTo, type?, currency? }`.
On web, computation moves server-side: a new `v1/transactions/queries:summarize` that reuses
the bounded-scan machinery from `v1/dashboard/helpers.ts` (`collectMatching` with a date
window anchor) or the aggregate component (D5). Native keeps computing locally over Drift.

### Kept (30), with fixes

- Accounts (6): `listAccounts` (honor `includeArchived`), `getAccount`,
  `getAccountBalance`, `createAccount`, `updateAccount`, `archiveAccount`.
- Categories (5) / Tags (5): `list*` honors `includeArchived` on web (add backend `list`
  with archived variant if `listActive` is the only query), `get*`, `create*`, `update*`,
  `archive*`.
- The `get*` tools stay deliberately, even with entities in the prompt: they are the
  refresh/disambiguation path when data changed mid-session or the snapshot is confusing.
  Their descriptions say exactly that ("use when the context snapshot may be stale or a
  name is ambiguous").
- Transactions (8): `listTransactions` (absorbs recent; all-optional args),
  `getTransaction`, `addExpense`, `addIncome`, `addTransfer` (resolve D3 — decision below),
  `addBalanceAdjustment`, `updateTransaction` (absorbs tag/untag), `deleteTransaction`
  (description clarifies it archives / is restorable).
- Saved filters (4) and dashboard widgets (5): unchanged shapes; descriptions
  de-"native"-ed and enriched with the semantics the model currently has to guess:
  balance widgets are as-of-now and never date-bounded; breakdown excludes transfers;
  stored filter amounts are cents while tool args are display units; stale account ids
  drop out of balance sums; widths map to a 6-unit grid (full=6, two_thirds=4, half=3,
  third=2); `reorderDashboardWidgets` requires ALL ids.

**D3 decision needed (small):** make `addTransfer.categoryIdOrName` truly optional
(align web executor + verify `createTransfer` backend/native accept null) — or make it
required in the schema. Recommendation: optional; transfers are excluded from breakdowns
anyway, so a forced category is noise.

### New (5)

| Tool | Args | Executor behavior |
|---|---|---|
| `addMemory` | `{ content }` | Insert into `agentMemories`. Web → `v1/memories/mutations:create`; native → Drift (synced, works offline). |
| `updateMemory` | `{ id, content }` | Edit an existing memory (ids are injected in the prompt's memory block). Also the consolidation primitive: merging two memories = one `updateMemory` + one `forgetMemory`. |
| `forgetMemory` | `{ id }` | Archive (soft delete, tombstoned like other synced entities). |
| `updateSettings` | `{ language?, theme?, defaultCurrency? }` | `language`/`theme` are device-scoped: web executor calls setters exposed through a widened `AgentToolContext` (i18n + theme providers sit above `VoiceProvider`, so it can consume both); native injects `DisplaySettingsController` into `ToolExecutors`. `defaultCurrency` → `v1/users/mutations:updateDefaultCurrency` on web / synced userSettings path on native. Result states what changed and that language/theme apply to this device only. |
| `readSkill` | `{ slug }` | Returns the bundled skill body from `packages/shared/src/agent-skills/` (web imports TS; native reads the codegen'd Dart constants — §5). Unknown slug → `{ ok: false, error, availableSlugs }`. |

### Validation / parsing hardening (item 6 of the ask)

- One golden test per platform asserting the executor set exactly equals the shared tool
  names (fixes D7 — native gets the manifest via the codegen in §5).
- Cross-language parsing parity tests: same fixture table for `parseNaturalDate` /
  `parseTransactionDate` / `parseAmountToCents` run against `packages/shared/src/tools/parsing.ts`
  (vitest) and `apps/native/lib/voice/tool_parsing.dart` (dart test).
- Web `defineTool` zod envelope stays; align every schema with actual executor behavior
  (D2, D3) so validation and execution never disagree.
- Rewrite every arg description that lies or rambles (D6); keep the excellent
  date/time-confidence contract, but state it once in the prompt and once per arg, not in
  three slightly different phrasings.

## 4. System prompt redesign

All prompt text stays in `packages/backend/convex/live/createToken.ts` (it must be minted
into the token), but is rebuilt from sections:

```
buildSystemInstruction({ args }) =
  CORE_IDENTITY            // who Gaston is, what Wallet Bot is, what the session is
+ PLATFORM_NOTES[args.platform]   // 'native' | 'web': surface differences, where things live in the UI
+ CAPABILITIES             // movements, entities, summaries, dashboard — expanded
+ DASHBOARD_GUIDE          // rewritten with the real widget semantics (see §3 kept-tools list)
+ CORE_RULES               // existing rules, tightened
+ MEMORY_RULES             // when to save/update/forget; consult before asking; consolidate
+ SKILLS_INDEX             // slug + one-liner per skill; "call readSkill before answering
                           //  questions about policies, sync, data handling"
+ USER_CONTEXT             // rendered from the client-supplied context payload (§2.1)
+ DATE_LINE                // computed in args.timezone with args.locale (fixes D8)
```

CORE_IDENTITY gains explicitly (items 4 & 5 of the ask): "You are Gaston (shown as 'Gasti'
in the app), the built-in assistant of Wallet Bot, a personal expense-tracking app. You are
embedded in the {native mobile|web} app and operate the user's data through tools. The same
account, data, and dashboard are shared across the user's devices."

USER_CONTEXT payload, built by each client and sent in the mint request. The shape is a
shared type (`packages/shared`, mirrored to Dart by the §5 codegen); the server validates
it and enforces the caps — high limits, abuse-prevention only:

| Data | Cap (client-built, server-enforced) | Native source | Web source |
|---|---|---|---|
| User name + email | — | session/auth state | session/auth state |
| Settings: default currency, language pref, theme pref | — | userSettings + `DisplaySettingsController` | userSettings + localStorage prefs |
| Active accounts (id, name, currency, color, archived flag) | 100 | Drift | `accounts.queries.list` |
| Active categories / tags (id, name, parent) | 200 each | Drift | `listActive` |
| Recent transactions (name, amount, currency, type, account, category, date) | 50 | Drift | `transactions.queries.recent` |
| Memories (id + content) | 200 | Drift (synced table) | `v1/memories` query |

Hard cap on the serialized block (proposed 32 KB); the server truncates with an explicit
marker rather than rejecting the mint. The rendered block is prefixed with: "Snapshot taken
when the session started. Tools are the source of truth; anything created during the
session exists even if absent here."

MEMORY_RULES (item 9): save a memory when the user states a durable preference or fact
("if I don't say the account, use Galicia", "my salary lands on the 1st", "call my cash
account 'efectivo'"); apply memories silently instead of re-asking; never store secrets or
one-off transaction details; forget on request. And the consolidation duty: when the memory
block contains duplicates, contradictions, or entries made obsolete by newer ones, merge or
rewrite them (`updateMemory`) and delete the leftovers (`forgetMemory`) — keep the set
small, current, and non-overlapping.

## 5. Shared→native codegen (one mechanism, four problems)

A small checked-in codegen script (`pnpm run generate:agent`, node, in `packages/shared`)
emits `apps/native/lib/voice/agent_generated.dart` containing:

1. `kAgentToolNames` — the tool manifest (enables the D7 parity test),
2. `kAgentModel`, `kAgentVoiceName` — kills the D4 duplication (`createToken.ts` and the
   generated Dart both import/derive from `packages/shared/src/tools/constants.ts`),
3. `kAgentSkills` — slug/title/body constants for `readSkill`,
4. the context-payload shape (field names + caps from §4), so native builds the same
   payload the server validates.

CI check (or a unit test) that the generated file is up to date with shared sources.

## 6. Web reconnection & history (fixes the confirmed bug)

Port native's proven design into `apps/web/src/hooks/use-voice.ts` + a new
`apps/web/src/lib/voice-seed.ts` (TS mirror of `buildConversationSeed`, same folding rules,
6000-char front-truncation, pending-text de-duplication):

1. In-memory conversation event log (the `kConversationEventTypes` set) alongside
   `messages` — the substrate for the seed.
2. Auto-reconnect with exponential backoff (2^(n-1) s, cap 30 s), reset on setup complete;
   connection-generation guard against late callbacks from superseded sockets;
   pre-emptive reconnect on `goAway`; fresh single-use token per attempt.
3. On `onclose`: keep the transcript, keep `pendingTextRef` (stop dropping typed turns),
   mark the history session `suspended` not `ended` (D10), schedule reconnect.
4. After setup: send the seed as `clientContent` with `turnComplete: false`, then flush
   queued text — same ordering contract as native.
5. Remove the transcript wipes: `startVoiceSession` (`add.tsx:660-664`), the
   typed-after-drop path (`use-voice.ts:1008-1018`), and `detach`'s disconnected-wipe
   (`use-voice.ts:1098-1120`). Only the explicit End action clears, like native.
6. `pagehide`/`visibilitychange` flush for the history outbox (D9).
7. Tests mirroring native's: seed construction, offline-typed flush order, no-wipe on drop.
8. Update `docs/web-parity-backlog.md` item 1.5 and `docs/voice-session-lifecycle.md` (D11).

Out of scope (agreed): page-reload transcript restore.

## 7. Compatibility gating (no feature flag)

The overhauled agent ships as the agent — no `agentV2` flag, no dark launch. What remains
is pure version compatibility: the mint must not declare a tool the connecting client
cannot execute — an old native binary answering `addMemory` with "Unknown tool"
mid-conversation is worse than not offering it. `requestLiveToken` already receives
`platform` + `appVersion` (§2.1); reuse the `config/helpers.ts` version comparison so each
new tool family carries a minimum client version per platform. Web (always fresh) is
unrestricted. Clients that send no context payload (old builds) get the rewritten base
prompt without the USER_CONTEXT block.

## 8. Phases

Ordered so churn never happens twice on the same file. Each phase is independently
shippable and replaces current behavior outright when it merges.

| Phase | Content | Main risk |
|---|---|---|
| **1. Tool surface restructure + defect sweep** | Removals/merges from §3, all description/schema rewrites (D1–D3, D6), parity tests + parsing fixtures, `summarizeTransactions` backend query (D5), codegen from §5 (D4, D7). Both executors change once. | Native/web executor drift — mitigated by the new golden tests. |
| **2. Prompt sections + client context payload** | `createToken.ts` refactor into sections; `requestLiveToken` args (platform/appVersion/locale/timezone + context payload); shared payload type + server-side validation and caps; both clients build and send the payload; date line in user tz (D8). | Prompt regressions and payload-size edge cases — covered by mint unit tests with oversized payloads. |
| **3. Web reconnection parity** | §6 in full. | Seed/dedup edge cases — covered by ported native tests. |
| **4. Skills** | `packages/shared/src/agent-skills/` + `readSkill` + SKILLS_INDEX. Initial set (draft, to confirm): `sync-and-offline`, `accounts-and-currencies`, `dashboard-filters-cookbook`, `dates-and-time-confidence`, `privacy-and-data`. | Content accuracy — each skill reviewed against the code it describes. |
| **5. Settings tool** | `updateSettings` + context widening on web, `DisplaySettingsController` injection on native. | Provider lifetimes (app-scoped controller vs account-scoped executors) — pass by reference at factory construction, verified on account switch. |
| **6. Memory (schema v4)** | `agentMemories` synced table end-to-end: Convex schema + sync pull/push + tombstones, `v1/memories` endpoints, Drift v3→v4 with `onUpgrade` + migration artifacts + integrity tests, `minSupportedVersion` bump both platforms in the same change, memory tools + MEMORY_RULES (incl. consolidation) + context-payload inclusion. **Requires explicit team agreement before starting (CLAUDE.md rule).** | The coordinated bump: old clients must fail closed on sync while staying usable offline — follow `docs/schema/README.md` to the letter. |

After each phase: `pnpm run typecheck` (root), `pnpm run lint` (apps/web), native tests,
and a `docs/riesgos.md` review — Phase 3 mitigates the existing web-conversation-loss risk;
Phase 6 adds a new risk entry (sync-protocol change / stranded old clients).

## 9. Open questions

1. `addTransfer` category: confirm "optional" (recommended) — needs a check that backend
   `createTransfer` and native accept a null category.
2. Initial skill list in Phase 4: confirm/extend the five drafted slugs.
3. Memory cap: proposed 200 per user (beyond it, the agent is told to consolidate before
   adding; the executor rejects the add with a "consolidate first" error).
4. Does `updateSettings` deserve a confirmation rule in the prompt ("announce the change,
   don't ask permission") — or should theme/language changes be apply-then-mention?
