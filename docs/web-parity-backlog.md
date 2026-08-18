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

---

## 1. Features to implement on web

Ordered by what the user loses.

### 1.1 Advanced transaction filtering

Native's filter model (`apps/native/lib/data/models/transaction_filter.dart`)
carries nine dimensions plus a boolean condition tree. Web's
(`apps/web/src/pages/activity/helpers.ts`) carries four.

| Dimension | Native | Web Activity |
|---|---|---|
| type (multi-select) | yes | single-select chip row only |
| status (pending / cleared) | yes | missing |
| date preset (today, week, month, last month, year) | yes | missing (absolute range only) |
| absolute date range | yes | yes |
| accounts + direction (source / destination / either) | yes | ids only |
| categories | yes | yes |
| tags + match any/all + includeSubtags | yes | ids only, implicit "any" |
| currency scope | yes | missing |
| amount min / max | yes | missing |
| text | yes | yes |
| AND / OR / NOT nested group editor | yes | missing |

Native's tree editor: `apps/native/lib/components/filter_sheet.dart` (`_GroupEditor`,
`_ConditionEditor`).

The model is **already ported to TypeScript** in
`packages/shared/src/dashboard/filter.ts`, and the backend already evaluates it
in `packages/backend/convex/v1/dashboard/helpers.ts`. Web's Activity re-derived
a flat `TransactionFilters` type instead of using it. The missing work is a UI
plus a query path, not a model.

### 1.2 Search and filtering are page-scoped on web

Native filters in SQL over the whole local database
(`apps/native/lib/data/queries/transaction_query.dart`). Web narrows
server-side by one account *or* one category plus a date range, then filters the
loaded page in JS, auto-loading at most 1000 rows
(`apps/web/src/pages/activity/index.tsx`, `REFILL_THRESHOLD` / `AUTO_LOAD_CAP`).

Consequence: on web a text search, a type chip, a multi-account selection or a
tag filter silently misses matches older than the first ~1000 transactions.

The backend has no index-backed text search at all. A search index fixes this
for both clients.

### 1.3 Nine agent tools stubbed as `native_only` on web

`apps/web/src/lib/agent-tools/executors.ts` returns
`{ ok: false, error: 'native_only' }` for:

- `listSavedFilters`, `createSavedFilter`, `updateSavedFilter`, `archiveSavedFilter`
- `listDashboardWidgets`, `createDashboardWidget`, `updateDashboardWidget`,
  `reorderDashboardWidgets`, `archiveDashboardWidget`

All nine backend mutations exist
(`packages/backend/convex/v1/dashboard/mutations.ts`) and web's own dashboard
already calls them (`apps/web/src/pages/home/widget-sheet.tsx`). The stubs are
stale.

Related: the shared system prompt still instructs the model to say *"web
dashboard parity is not available yet"*
(`packages/backend/convex/live/createToken.ts`). That sentence is now false and
should be updated in the same change.

### 1.4 Voice history is never persisted on web

Native records every Live event to Drift and replicates it to `voiceSessions` /
`voiceSessionEvents` (`packages/backend/convex/v1/voice/sessions.ts`, via
`apps/native/lib/voice/voice_session_remote_sync.dart`). Web calls nothing under
`api.v1.voice` — the transcript lives in React state and is lost on reload.

The data-export and retention contract in `docs/voice-data-export.md` therefore
covers native conversations only.

### 1.5 Voice sessions do not survive a dropped socket on web

Native holds a resumption handle, handles `goAway`, and reconnects with
exponential backoff
(`apps/native/lib/voice/gemini_voice_expense_command.dart`). Web's `onclose`
flips to `disconnected` and the conversation ends
(`apps/web/src/hooks/use-voice.ts`).

The ephemeral token already negotiates `sessionResumption` and
`contextWindowCompression`, so the server side is ready.

### 1.6 Dashboard widget filters are narrower on web

Native's widget sheet opens the full filter editor, hiding only status
(`apps/native/lib/components/dashboard/add_widget_sheet.dart`). Web's inline
editor offers types, date preset, accounts, categories and currency — no tags,
no amount, no custom range — and renders advanced filters read-only
(`apps/web/src/pages/home/widget-sheet.tsx`).

A widget configured on native can be opened on web but not fully edited.

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

### 1.9 `recurringExpense` flag toggle

Registered as a known flag for both platforms
(`packages/backend/convex/featureFlags/utils.ts`) but only read by native's
expense form (`apps/native/lib/screens/transaction_form.dart`). Enabling the flag
does nothing on web.

### 1.10 Web's create-account ignores the user's default currency

Native seeds the picker from `DefaultCurrencyController`
(`apps/native/lib/screens/create_account.dart`); web hardcodes
`DEFAULT_CURRENCY` (`apps/web/src/pages/accounts/account-form.tsx`). A web user
who set USD in Settings still gets ARS pre-selected.

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

### 2.1 Generated names are not localized on web

Native maps canonical Spanish names to the active locale at render time —
`transactionName()` and `dashboardTitle()` in `apps/native/lib/l10n/l10n.dart`,
applied at six call sites. Web has no equivalent, so an English web user sees
`Ajuste de saldo`, `Balance inicial` and `Gastos del mes` verbatim.

### 2.2 The same action writes two different names

Creating an account with an opening balance writes a transaction named
`Balance inicial` on native
(`apps/native/lib/data/repositories/account_repository.dart`) but
`Ajuste de saldo` on web, which omits `name` and takes the backend default
(`packages/backend/convex/v1/transactions/mutations.ts`). One user's ledger ends
up carrying both.

### 2.3 Native's transaction-detail screen is not localized

`apps/native/lib/screens/transaction_details_sheet.dart` has roughly 38
hardcoded Spanish strings against 3 `l10n` calls — `Descripción`,
`Fecha estimada`, `Cuenta destino`, `Guardar`, `La actividad ya no existe`, and
so on. The row identity labels in `apps/native/lib/screens/activity.dart`
(`'Cuenta: '`, `'Categoria: '` — also misspelled) are hardcoded too.

Web's equivalent is fully internationalized. This is the one item where **native
is behind web**.

### 2.4 Two ID schemes on web

Native deliberately consolidated on a single UUID v4 helper
(`apps/native/lib/data/ids.dart`, whose comment records removing exactly this
problem). Web has three `newId` definitions across two schemes:

- `crypto.randomUUID()` — `apps/web/src/pages/add-manual.tsx`,
  `apps/web/src/pages/home/widget-sheet.tsx`,
  `apps/web/src/lib/agent-tools/executors.ts`
- `Date.now() + Math.random()` — `apps/web/src/pages/accounts/index.tsx`,
  `apps/web/src/pages/insights.tsx`,
  `apps/web/src/pages/accounts/account-detail.tsx`

These ids are synced and shared between clients.

---

## 3. Where web is ahead of native

- **Feature-flag admin UI** — `apps/web/src/pages/admin/feature-flags.tsx`
  (defaults plus per-user overrides). No native equivalent; flags can only be
  administered from web.
- **Microphone device picker** in the voice screen — `apps/web/src/pages/add.tsx`.
- **Transaction counts on tag chips** in Insights —
  `apps/web/src/pages/insights/tags-view.tsx`. Native shows the chip only.

---

## 4. Notes for the sync effort

1. **`packages/shared` is the parity mechanism that already works.** Filters,
   widget options, tool definitions and date/amount parsing live there, and
   wherever both clients consume it — dashboard seeding, widget rendering, agent
   schemas — parity is near-exact. The default dashboards even share
   deterministic seed ids so a device and the browser converge instead of
   duplicating the layout. Where a client re-derived a model instead (web's
   `TransactionFilters` versus shared's `SimpleFilter`) is precisely where the
   gap opened. New cross-platform concepts should land in `shared` first.

2. **Confirmed already at parity**, checked and requiring no action: icon
   catalogs (11 account, 14 category, name for name), the 21-colour palette,
   window size-class breakpoints (600 / 1000), list-detail presentation rules,
   transaction-detail editing including balance before/after, account, category
   and tag details, the manual transaction form (inline entity creation,
   transfer swap, dual amounts), all four widget types with pie/bar/line,
   dashboard grid drag plus width and delete, the 11 agent-editable action
   cards, and the settings screen.

3. **Dead code on both sides.** `ActivitySummaryCard` is defined and never used
   in either app (`apps/native/lib/components/activity_summary_card.dart`,
   `apps/web/src/pages/activity/activity-summary-card.tsx`), along with web's
   `aggregateMonth` and `monthRange` helpers. Removing it from one app only
   would read as a parity regression later, so handle it in one change.
