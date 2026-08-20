# Web parity backlog

Features present in the native app (`apps/native`) that the web app
(`apps/web`) does not have, plus the behavioural differences that make the two
clients disagree on shared data.

Compiled from a full side-by-side read of both codebases: every native screen
against its web route, `packages/shared`, the Convex functions each client
calls, and both i18n catalogs. Every entry points at a file. Nothing here was
verified at runtime — these are source-level findings.

The offline-first local database and sync engine are the known architectural
difference and are out of scope; this list is what sits on top of them.

Closed entries move to § 5 rather than being deleted, and keep their original
numbers so the ids stay quotable. Last updated 2026-08-19.

---

## 1. Features to implement on web

Ordered by what the user loses.

### 1.5 Voice sessions do not survive a dropped socket on web

Native holds a resumption handle, handles `goAway`, and reconnects with
exponential backoff
(`apps/native/lib/voice/gemini_voice_expense_command.dart`). Web's `onclose`
flips to `disconnected` and the conversation ends
(`apps/web/src/hooks/use-voice.ts`).

The ephemeral token already negotiates `sessionResumption` and
`contextWindowCompression`, so the server side is ready.

Related and also open: native keeps the session alive when the screen is left,
while web tears it down when the route unmounts.

Closing 1.4 wrote the observation into the history: web records the server's
`session_resumption_update` and `go_away` signals but does nothing with them, and
marks a dropped session `ended` where native marks it `suspended`. Both change
when this lands.

### 1.7 No telemetry on web

Native emits `app.started` plus four business metrics — user accounts, financial
accounts, movements, transfers — to `/telemetry/events` and `/telemetry/metrics`
(`apps/native/lib/telemetry/business_metrics.dart`). Web emits nothing.

Every dashboard in `docs/observability-grafana.md` and
`docs/business-metrics-feature.md` is currently blind to web usage, and the two
platforms' numbers are not comparable.

### 1.8 Remote config banners have no web consumer

The backend serves banners with placements `home` and `auth`
(`packages/backend/convex/config/helpers.ts`), rendered natively by
`apps/native/lib/app_config/app_config_banner_list.dart` with markdown and
actions. Web has no consumer, so announcements, maintenance notices and incident
messaging cannot reach web users.

The version-gating half of that config is genuinely native-only and should stay
so.

### Deliberately architectural — decide, do not drift

Local (no-account) mode, multiple accounts with a switcher
(`apps/native/lib/screens/home.dart`), the sync-status pill, the re-auth banner
and version gating all follow from the offline-first native design.

Of these, only **multi-account switching** is portable to web in principle, and
only at the cost of the current single-session better-auth model. This deserves
an explicit decision so it is not treated as a bug later.

---

## 2. Silent divergences

Same feature on both clients, different result. These matter more than missing
features because they produce inconsistent data or display for the same user
across devices.

### 2.3 Native's transaction-detail screen is not localized

`apps/native/lib/screens/transaction_details_sheet.dart` has roughly 38
hardcoded Spanish strings against 3 `l10n` calls — `Descripción`,
`Fecha estimada`, `Cuenta destino`, `Guardar`, `La actividad ya no existe`, and
so on. The row identity labels in `apps/native/lib/screens/activity.dart`
(`'Cuenta: '`, `'Categoria: '` — also misspelled) are hardcoded too.

Web's equivalent is fully internationalized. This is one of the items where
**native is behind web**.

---

## 3. Where web is ahead of native

- **Feature-flag admin UI** — `apps/web/src/pages/admin/feature-flags.tsx`
  (defaults plus per-user overrides). No native equivalent; flags can only be
  administered from web.
- **Microphone device picker** in the voice screen — `apps/web/src/pages/add.tsx`.
- **Transaction counts on tag chips** in Insights —
  `apps/web/src/pages/insights/tags-view.tsx`. Native shows the chip only.
- **Currency list in the inline "new account" dialog** — the web transaction
  form offers the full shared catalog, while native's still offers four hardcoded
  options (`apps/native/lib/screens/transaction_form.dart:_mockCurrencyOptions`).
  Introduced by closing 1.10.
- **Text search reaches the whole history from one query** — web now searches
  server-side over indexed text (§ 5, 1.2). Native searches its whole local
  database too, so this is not a user-visible gap, but the *shape* differs: web
  can search without having synced every row locally.

---

## 4. Notes for the sync effort

1. **`packages/shared` is the parity mechanism that already works.** Filters,
   widget options, tool definitions and date/amount parsing live there, and
   wherever both clients consume it — dashboard seeding, widget rendering, agent
   schemas — parity is near-exact. The default dashboards even share
   deterministic seed ids so a device and the browser converge instead of
   duplicating the layout. Where a client re-derived a model instead (web's old
   flat `TransactionFilters` versus shared's `SimpleFilter`) is precisely where
   the gap opened — that re-derived model is gone as of § 5, 1.1, and its
   deletion is what closed three separate entries at once. New cross-platform
   concepts should land in `shared` first.

2. **Confirmed already at parity**, checked and requiring no action: icon
   catalogs (11 account, 14 category, name for name), the 21-colour palette,
   window size-class breakpoints (600 / 1000), list-detail presentation rules,
   transaction-detail editing including balance before/after, account, category
   and tag details, the manual transaction form (inline entity creation,
   transfer swap, dual amounts), all four widget types with pie/bar/line, the
   whole dashboard grid editor (§ 5, 1.11), the 11 agent-editable action cards,
   and the settings screen.

3. **Dead code on both sides.** `ActivitySummaryCard` is defined and never used
   in either app (`apps/native/lib/components/activity_summary_card.dart`,
   `apps/web/src/pages/activity/activity-summary-card.tsx`), along with web's
   `aggregateMonth` and `monthRange` helpers. Removing it from one app only
   would read as a parity regression later, so handle it in one change.

4. **A shared control should keep a shared summary.** The activity filter bar's
   badge and chip row report four groups (accounts, categories, tags, date) on
   both clients, because that is what `transaction_filters_bar.dart` counts —
   even though the sheet behind it edits nine dimensions. A filter on amount or
   currency is therefore invisible in the bar on *both* platforms. Widening it
   is a two-client change; doing it on one side would open a new divergence.

---

## 5. Closed

Kept for the record, with what closed each one. Nothing below has been verified
at runtime; every entry is a source-level change that typechecks and lints.

### 1.1 Advanced transaction filtering — closed 2026-08-19

Web's Activity dropped its own flat four-dimension `TransactionFilters` for the
canonical `SimpleFilter` in `packages/shared/src/dashboard/filter.ts`, and
`apps/web/src/components/filters/` ports native's
`apps/native/lib/components/filter_sheet.dart`: simple mode over all nine
dimensions (type, status, date presets plus absolute range, accounts with
direction, categories, tags with subtags / `match` / `includeSubtags`, currency,
amount, text) and advanced mode with the nested AND/OR/NOT tree, depth 2, the
same per-field operators and the same default conditions. The `hiddenSections`
contract matches too — the activity bar hides text and status, the widget sheet
hides status.

### 1.2 Search and filtering are page-scoped on web — closed 2026-08-19

`v1/transactions/queries:listByFilter` evaluates the canonical tree server-side
over an index-anchored stream, paginating *after* the predicate, so a page is a
page of matches. `transactions` gained `search_name` and `search_description`
search indexes for the one dimension no ordered index can bound.

Residual bounds are tracked as **R-019** in `docs/riesgos.md`: the ordered scan
stops at `MAX_SCAN` rows read per page, a text-only filter considers only the
best `MAX_SEARCH_CANDIDATES` per index, and a search index cannot match an
infix (`bucks` inside `Starbucks`), which native's `LIKE '%…%'` can. None of
that is surfaced in the UI yet.

### 1.3 Nine agent tools stubbed as `native_only` on web — closed 2026-08-18

`apps/web/src/lib/agent-tools/executors.ts` ports them from
`apps/native/lib/voice/tool_executors.dart` with the same arguments, error
strings, result shapes and stored JSON. The system prompt in
`packages/backend/convex/live/createToken.ts` no longer tells the model that web
dashboard parity is missing.

### 1.4 Voice history is never persisted on web — closed 2026-08-19

`apps/web/src/lib/voice-history.ts` replicates a Live session to `voiceSessions`
/ `voiceSessionEvents` through the same V1 mutation native uses, with native's
event vocabulary (`type`, `direction`, `modality`), its 50-event batches, its
one-second debounce and its five-second retry. Web's `ownerId` comes from the new
`v1/users/queries:getMyId`, derived server-side, so the account-boundary check
behaves the same for both clients.

Three deliberate divergences, all recorded in `docs/voice-data-export.md`: the
outbox is in memory, so a tab closed inside the flush window loses the tail; only
the semantic log is uploaded, not native's raw protocol firehose or its per-PCM
-chunk rows (thousands a minute, which SQLite absorbs and a browser round-trip
does not); and a dropped socket writes status `ended` rather than native's
`suspended`, because web cannot resume it (1.5).

There is still no export surface for a web user's history — `exportSessionJson`
and friends are Drift APIs, so Convex holds the only copy.

### 1.6 Dashboard widget filters are narrower on web — closed 2026-08-19

The widget sheet uses the same `FilterSheet` as the activity list, so a widget
configured on native is now fully editable on web — tags, amount, custom ranges
and advanced trees included. The read-only advanced-filter notice is gone.

### 1.9 `recurringExpense` flag toggle — closed 2026-08-18

The toggle exists on web's expense form, display-only and never persisted,
exactly as `_isRecurringExpense` behaves on native. The flag registry still
records the feature itself as not built.

### 1.10 Web's create-account ignores the user's default currency — closed 2026-08-18

Both surfaces — `apps/web/src/pages/accounts/account-form.tsx` and the inline
"new account" dialog in `apps/web/src/pages/add-manual.tsx` — now seed from the
user's default currency, null until the user picks, with a live fallback, the
same rule as `apps/native/lib/screens/create_account.dart`. Left web ahead of
native on the inline dialog's currency list (§ 3).

### 2.1 Generated names are not localized on web — closed 2026-08-19

`apps/web/src/lib/i18n/generated-names.ts` ports `transactionName` and
`dashboardTitle` from `apps/native/lib/l10n/l10n.dart`, mapping the two generated
transaction names and the six seeded dashboard titles at render time and
accepting either spelling, since either client may have written the row. Applied
at the four places web renders a transaction name (activity list, entity recent
lists, the agent action card, the dashboard list widget) and the six where it
renders a widget title. Editable fields keep the stored value — localizing them
would persist the localized copy over the canonical name.

### 2.2 The same action writes two different names — closed 2026-08-18

Web passes `name: 'Balance inicial'` when creating an account's opening balance,
the canonical name native writes, instead of falling through to the backend's
`Ajuste de saldo` default. The string stays canonical Spanish on purpose; making
it read correctly for an English web user is 2.1.

### 1.11 The web dashboard grid was a fraction of the native one — closed 2026-08-19

Web had two of the four drop affordances (swap onto a tile, move onto a free
unit) and nothing else. Missing: the between-rows band that opens a new row
(`_NewRowDropZone`), the between-tiles seam that wedges a tile into a row and
reflows it (`_RowInsertZone`), the dashed `+` placeholder in every empty run
that adds a widget at that exact cell capped to the free span (`_GapVisual` +
`showAddWidgetSheet(at:, maxUnits:)`), the press-and-hold that arms the editor,
the tap that opens the activity list on the tile's filter
(`_activityFilterFor`), and the delete confirmation. Widths that did not fit
were disabled instead of sliding the tile left or clamping it
(`DashboardGridLayout.resize`), and every move waited out a server round-trip
before appearing.

All of it landed by moving the engine itself into
`packages/shared/src/dashboard/layout.ts` — `placeAt`, `dropOnCell`, `swap`,
`insertRowAt`, `insertInRow`, `canInsertInRow`, `nudge`, `enabledDirections`,
`resize`, `fitWidth`, `freeRuns`, `normalizeLayout` — ported from
`dashboard_layout.dart`, so the two clients no longer each re-derive the moves.
`apps/web/src/pages/home/dashboard.tsx` renders the affordances over it and
writes through `saveLayout` with a Convex optimistic update.

Verified in headless Chromium against the real components: 40 checks over the
drop geometry, `elementsFromPoint` ordering, every drop kind, the menu's
enabled states, the `+` targeting, the confirmation, the view-mode gestures,
the optimistic move and its rollback, touch hold-then-drag, and the wide-window
band reflow.

Left web ahead of native on two points, both recorded in
`docs/home-dashboard.md`: unavailable widths are disabled rather than inert, and
an overlapping same-row swap is refused instead of persisted.

### 2.4 Two ID schemes on web — closed 2026-08-18

`apps/web/src/lib/new-id.ts` is the single helper and returns
`crypto.randomUUID()`, the scheme native settled on
(`apps/native/lib/data/ids.dart`) and the one the backend generates and
documents. The three inlined definitions are gone.
