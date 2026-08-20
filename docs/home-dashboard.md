# Home Dashboard — Design

Customizable home screen for the native app: an ordered set of configurable
widgets showing summaries (spend, balance, recent activity) over user-defined
filters.

**Scope (v1):** native-only · all widget types · saved filters · layout stored
locally (Drift), modeled to sync later.

---

## Two primitives

Everything is composed from **Filters** (what data) and **Widgets** (how it's shown).

### Filter ("Saved View")

A first-class, named, reusable spec selecting a slice of transactions. Referenced
by widgets and quick-access shortcuts. See [Filter structure](#filter-structure)
below for the full shape.

Every field is optional; absent = unconstrained. Empty filter (`{}`) = all
transactions. Store `dateRange` as a **relative enum**, resolved at render time,
so "this month" rolls forward instead of freezing.

### Widget

A visual instance bound to a Filter + display options.

| Widget | Binds to | Shows | Default width |
|---|---|---|---|
| **Stat block** | Filter + aggregation (sum / net / count) + currency | one number, optional Δ vs previous period | third / half |
| **Balance card** | account(s) or currency | current balance *as of now* (not date-bounded) | half / full |
| **Transaction list** | Filter + limit | recent N matching rows, tap → full filtered list | full |
| **Breakdown chart** | Filter + group-by (category / account / time) | pie / bar / line | full |

---

## Filter structure

### Dimensions

| Dimension | Source field(s) | Shape / operator | Notes |
|---|---|---|---|
| **Type** | `type` | any-of `[expense, income, transfer, balance_adjustment]` | empty = all |
| **Status** | `status` | `pending` / `cleared` / `any` | |
| **Date** | `date` | relative preset **or** absolute `{from,to}` | the only range dimension |
| **Accounts** | `accountId` **+** `toAccountId` | any-of `ids[]` **+ direction** | direction handles transfers (⚠️) |
| **Categories** | `categoryId` | any-of `ids[]` | |
| **Tags** | via `transactionTags` | any-of / all-of `ids[]` **+ includeSubtags** | subtags are just tags (⚠️) |
| **Currency** | `currency` | single scope | required by numeric widgets |
| **Amount** | `amount` | range `{min?, max?}` | only valid with a currency; compares absolute value |
| **Text** | `name` / `description` | substring `search` | ⚠️ no backend search index yet |

### Subtleties

- **⚠️ Accounts need a direction.** Transfers have a source (`accountId`) and a
  destination (`toAccountId`). The account filter carries `direction`:
  `source` / `destination` / `either` (default `either`).
- **⚠️ Tags need match-mode + subtag expansion.** `match: any | all`; and
  `includeSubtags` expands a selected parent tag to all descendants (via `parentId`).
- **⚠️ Amount is coupled to currency.** A range over mixed currencies is
  meaningless, so `amount` is only valid when `currency` is set. Sign is implied
  by `type`, so the range compares absolute value.

### Combination model — one canonical tree, two UIs

The stored representation is a **condition tree** (group of AND/OR with optional
NOT, nesting conditions or sub-groups). The flat filter is just a constrained
*view* over this tree — there is only ever **one** stored format and **one**
evaluation engine.

```jsonc
// Canonical model (stored in savedFilters.config)
Group     = { combinator: "and" | "or", not?: boolean, children: (Group | Condition)[] }
Condition = { field, operator, value }
```

- **Fields:** `type`, `status`, `date`, `account`, `category`, `tag`, `currency`, `amount`, `text`.
- **Operators** (per field): sets (`account`/`category`/`type`/`status`) → `in` / `not in`;
  `date` → `between` / `relative`; `amount` → `between` / `>=` / `<=`; `text` → `contains`;
  `tag` → carries `match: any | all` + `includeSubtags`.
- The old per-dimension `mode: include | exclude` becomes `in` / `not in` (or a
  `not` on the enclosing group).

**Two editors over the same tree:**

- **Simple mode (default, 90% of users):** dimension-per-row chips, exactly the
  table above. Opens only for trees that are *simply representable* — root is a
  single `and`, depth ≤ 1, each field appears once (an `in`-list counts as one),
  no `not`/nested groups.
- **Advanced mode (opt-in):** full tree editor with AND/OR toggle, NOT, and
  nested groups. **Nesting depth is capped** (≤ 2–3 levels, Airtable-style) to
  keep it legible. A tree that isn't simply representable shows a read-only
  summary in simple mode.

This is what lets disjunction across dimensions
("`category = Food` **OR** `tag = work`") and correlated branches
("`(Food AND >50k)` OR `(Transport AND tag=trip)`") exist without complicating
the default UX — the advanced editor is hidden until summoned.

### Shape examples

```jsonc
// Simple filter — expenses, BBVA, Food-or-Transport, this month.
// Simply representable → renders as chips.
{
  "combinator": "and",
  "children": [
    { "field": "type",     "operator": "in",       "value": ["expense"] },
    { "field": "account",  "operator": "in",        "value": ["<bbva>"], "direction": "either" },
    { "field": "category", "operator": "in",        "value": ["<food>", "<transport>"] },
    { "field": "date",     "operator": "relative",  "value": "this_month" },
    { "field": "currency", "operator": "in",        "value": ["ARS"] }
  ]
}

// Advanced filter — Food OR anything tagged `work`, this month.
// Not simply representable → advanced editor only.
{
  "combinator": "and",
  "children": [
    { "field": "date", "operator": "relative", "value": "this_month" },
    { "combinator": "or", "children": [
      { "field": "category", "operator": "in",  "value": ["<food>"] },
      { "field": "tag",      "operator": "in",  "value": ["<work>"], "match": "any", "includeSubtags": true }
    ]}
  ]
}
```

> **Store the tree from day one, build only the simple editor in v1.** Adding the
> advanced editor later is then purely additive — no migration of saved filters,
> no engine rewrite.

---

## Layout: manual grid

The dashboard is a **manual 6-unit grid**. Each widget keeps a `width`
(`full` = 6 units · `two_thirds` = 4 · `half` = 3 · `third` = 2) **and** an
explicit placement — `{row, col}` (0-based row, 0-based starting column in grid
units, with `col + width.units <= 6`). The placement is stored inside the
widget's `options` JSON under the `layout` key, so it rides the existing opaque
`options` sync with **no schema change** on Drift or Convex.

```
┌─────────────────────────────┐  row 0      — Balance card (full)
├──────────┬──────────┬───────┤
│ third    │ third    │ third │  row 1      — three stats, cols 0 / 2 / 4
├──────────┴───┬──────┴───────┤
│ two-thirds   │              │  row 2      — tile at col 0, cols 4–6 left empty
├──────────────┴─────────────┤
│ full-width breakdown chart  │  row 3
└─────────────────────────────┘
```

Users place tiles freely: drag a tile onto any empty cell (it auto-shrinks to
the largest width that fits the free span), drop it onto another tile to swap,
or drop it between rows to **create a new row**. Empty *rows* collapse
automatically; horizontal gaps within a row are kept. The floating tile menu
also offers up/down/left/right arrows for one-cell nudges and the
`1/3 · 1/2 · 2/3 · 1/1` width controls.

**Edit mode always keeps one spare row below the board.** Without it the bottom
row is a dead end: two `third`s side by side there can neither slide sideways
nor move up, so neither can be shifted out of the way and neither can grow. The
spare row is a full-height (88dp) dashed drop area with its own `+`, not a
16dp band, and it only becomes a real row once something lands in it. The
down-nudge follows the same rule — it may move a tile onto a row that does not
exist yet, but *not* when the tile is alone on the last row, because that would
vacate the row it left and the empty-row collapse would put it straight back.
With the spare row present the last row drops its bottom insert band; the spare
row does that job more legibly.

The layout engine (`dashboard_layout.dart`) is pure Dart: it resolves stored
coordinates into placements (falling back to the legacy auto-flow for any widget
that predates manual placement, so old dashboards upgrade cleanly) and computes
moves, fits, swaps, row inserts, and empty-row collapse. The view coordinator
persists resolved coordinates for every widget once hydration is safe.
`position` is still written (row-major) so the non-editing read order and the
legacy fallback stay stable.

Persisted coordinates are treated as untrusted sync input. The resolver checks
that every widget has an integer non-negative coordinate, stays within the
6-unit grid, and does not overlap another widget. An invalid or mixed snapshot
renders immediately through the deterministic legacy auto-flow; after remote
hydration completes, `DashboardSection` compare-and-writes that safe layout in
one local transaction so a concurrent fresher merge cannot be overwritten.

---

## Data model (local Drift, sync-ready)

Both tables carry the standard sync columns (`id` UUID, `seq`, `isArchived`,
`createdAt`, `updatedAt`) so promoting them to synced Convex tables later is
additive, not a rewrite.

- **`savedFilters`** — `id`, `name`, `config` (JSON of the Filter fields above) + sync columns.
- **`dashboardWidgets`** — `id`, `type`, `filterId` (→ savedFilters, nullable for balance-by-account), `position`, `width`, `options` (JSON: title, aggregation, groupBy, limit, chartKind, comparePrevPeriod) + sync columns.

Widget `options.background` is optional and applies to every widget type:

```jsonc
// Fixed background
{ "mode": "fixed", "fixedColor": "#C8F2D8" }

// Value-based background. Thresholds use displayed units:
// money widgets use amount units (not cents), lists use row count,
// charts use the total of visible slices.
{
  "mode": "value",
  "value": {
    "low": 0,
    "high": 10000,
    "lowColor": "#FFCBCB",
    "betweenColor": "#FFE588",
    "highColor": "#C8F2D8"
  }
}
```

---

## Data sourcing (offline-first)

Widgets read **local Drift** via `watch()` streams — never Convex directly — so
the home screen works offline and updates reactively. Local aggregations to build:

- **Stat** — sum / net / count over filtered txns, currency-scoped, optional prev-period delta.
- **Balance** — sum of signed amounts per account, mirroring backend sign logic (expense −, income +, transfer − source / + dest, balance_adjustment = set).
- **List** — recent-N over a filter.
- **Chart** — group-by category / account / month.

Follow the existing `watch().map()` pattern in
`apps/native/lib/components/categories_view.dart`.

---

## Querying & indexes

A flat AND maps cleanly onto one index; a tree with **OR across dimensions does
not** — disjunction can't be served by a single index range, and a naive
evaluation would violate the project rule against full table scans /
load-all-then-filter-in-memory.

The unifying principle that solves it: **bound the scan with an index, then
predicate-filter the residual.** This is already how flat filters work today
(pick the best index from one dimension, let the engine filter the rest); the
only change for advanced filters is that the residual is a *tree* predicate
instead of a flat AND.

### v1 — native / Drift (SQLite)

**Essentially free.** The condition tree compiles directly to a SQL `WHERE`
clause (`AND` / `OR` / `NOT` / parentheses); a recursive Dart predicate is the
fallback. SQLite handles arbitrary boolean logic over one user's local dataset,
which is already bounded. Tag conditions become an `EXISTS` sub-query / join on
`transactionTags`. No index gymnastics needed beyond ordinary indexed columns.

This is the payoff of native-only + local reads: full filter power, now.

### Backend / web (future)

When these filters must run server-side, apply the anchor strategy:

1. **Anchor rule** — every served filter must bound its scan with an indexed
   dimension: a **date range** (the natural anchor — every dashboard widget has
   one) or an **account / category**. Validation rejects an unanchored,
   all-time, cross-dimension OR filter ("add a date range or account").
2. **Index the anchor, predicate the rest** — stream the anchor's index range
   ordered by `date` (paginated, descending) and evaluate the full condition
   tree as a **server-side `.filter()` predicate** over that bounded window. The
   index range is the bound (not a full scan); filtering happens *within* the
   paginated window (not load-all-in-memory) — both rules satisfied.
3. **Tags** — pre-resolve matching `transactionId`s via the `by_user_tag` index
   into a Set (expand subtags first; intersect for `all`), then membership-test
   in the predicate. Avoids N+1 lookups per candidate.
4. **Escape hatch (only if needed)** — for an anchorless OR, decompose the tree
   to **DNF** (OR-of-ANDs), run each conjunct on its best index, k-way-merge by
   `date` with `_id` dedup. More complex pagination; prefer the anchor rule and
   treat this as last resort.

Flat / simply-representable filters keep using the existing single-index path
unchanged — only advanced (disjunctive) filters take the anchor+predicate path.

---

## Semantic defaults

1. **"Spent" = sum of `expense` only** — own-account transfers aren't spending.
2. **Numeric widgets require a currency scope** — multi-currency filters show a
   per-currency breakdown, never a summed-across-currencies number.

---

## Dependencies

- `fl_chart` (`^1.2.0`) — breakdown chart (pie / bar / line). Installed; usage
  isolated in `apps/native/lib/components/dashboard/breakdown_chart_widget.dart`.
- `ReorderableListView` — built-in, no dep needed.

---

## Phasing

1. **Foundation** ✅ — Drift tables + local aggregation queries + layout/flow renderer.
2. **Widgets** ✅ — Stat, Balance card, Transaction list, and Breakdown chart (pie / bar / line, group-by category / account / month) renderers.
3. **Editing** ✅ — add / remove / reorder, width control, background options, and simple/advanced filter editing.
4. **Sync** ✅ (native + Convex) — both tables wired into `SyncEngine` and the backend push/pull.
5. **Web parity** ✅ — `convex/v1/dashboard/` serves layout, CRUD, seed and the
   aggregations straight to the web client (anchor + predicate, see § Querying);
   the filter model and the 6-unit layout engine live in
   `packages/shared/src/dashboard/` so both clients resolve and repair a stored
   layout identically; the UI is in `apps/web/src/pages/home/`. Web edits filters
   in **simple mode only** — an advanced tree renders read-only there.

> **Status:** the `savedFilters` + `dashboardWidgets` Drift tables persist the
> layout and sync through the existing `SyncEngine` ↔ Convex `sync/` pipeline
> (LWW, tombstones, per-user `seq`). The default dashboard auto-seeds once per
> device with **deterministic ids** (so concurrent fresh-device seeds converge
> instead of duplicating), guarded by `syncState.dashboardSeeded`. Local-only
> accounts seed immediately. Remote accounts wait until their initial pull has
> completed; pulled dashboard tombstones suppress seeding so an intentionally
> emptied dashboard is not resurrected. Editing lives
> in `apps/native/lib/components/dashboard/` (`dashboard_editor.dart`,
> `add_widget_sheet.dart`) and reuses `showFilterSheet`
> (`apps/native/lib/components/filter_sheet.dart`).
>
> The Breakdown chart widget (`fl_chart`, pie / bar / line, group-by category /
> account / month) is implemented in `breakdown_chart_widget.dart`, reading the
> reactive `SummaryRepository.watchBreakdown` aggregation. Its `groupBy` +
> `chartKind` live in the widget's `options` JSON, so it syncs through the
> existing `dashboardWidgets` table with no schema change.
>
> **Agent access:** native voice tools can list/create/update/archive saved
> filters and dashboard widgets, using the same canonical filter JSON and
> widget option JSON as the UI.
>
> **Web (2026-08-15):** the same tables are read through `v1/dashboard/queries`
> (`layout`, `stat`, `transactions`, `currencyBalance`, `breakdown`) and written
> through `v1/dashboard/mutations`. The web seed uses the **same deterministic
> ids** as `default_dashboard.dart`, so a device and the web app seeding one
> fresh account converge under LWW instead of duplicating, and it refuses to
> seed when a dashboard tombstone exists. As on native, a mouse starts dragging
> on movement while touch waits out a hold, so the page keeps its scroll.
>
> **Web editing is at parity (2026-08-19).** The whole
> `DashboardGridLayout` op set — `place`, `swap`, `insertRowAt`, `insertInRow`,
> `nudge`, `resize`, `fitWidth`, `enabledDirections` and the empty-row collapse —
> now lives in `packages/shared/src/dashboard/layout.ts`, so both clients compute
> the same move from the same snapshot. The web board offers all four native drop
> affordances (another tile to swap, a free unit to move and shrink to the run,
> the seam between two tiles to wedge into that row, a row's edge band to open a
> new row), the dashed `+` placeholder in every empty run that adds a widget
> right there capped to the free span, the floating menu's widths / nudges /
> edit / delete, a delete confirmation, and outside edit mode a tap that opens
> the activity list scoped to the tile's own filter plus a press-and-hold that
> arms the editor. Layout writes are optimistic (`withOptimisticUpdate`), so a
> dropped tile lands under the pointer and rolls back with a toast if the
> mutation fails.
>
> Two deliberate web-only refinements: a width the tile cannot take is
> **disabled** rather than silently doing nothing, and a same-row swap between
> unequal widths that would overlap is **refused** — `DashboardGridLayout.swap`
> on native still has that hole and would persist an overlap the resolver then
> discards to the legacy auto-flow.
>
> **Still pending:** the advanced (tree) filter editor on web.
