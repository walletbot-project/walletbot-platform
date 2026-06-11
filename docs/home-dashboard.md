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

## Layout: width, not nested rows

The dashboard is **one flat ordered list**. Each widget has a `position` and a
`width` (`full` / `half` / `third`). Narrower widgets flow and wrap into rows —
a "row of stat blocks" is just three `third`-width stats in sequence.

```
┌─────────────────────────────┐  full   — Balance card
├──────────┬──────────┬───────┤
│ third    │ third    │ third │  three stats → one row
├──────────┴──────────┴───────┤
│ full-width breakdown chart  │
├─────────────────────────────┤
│ transaction list            │
└─────────────────────────────┘
```

Flat list keeps reorder and future sync simple. Renders with a `Wrap` / flex
grouping; reorder via built-in `ReorderableListView`.

---

## Data model (local Drift, sync-ready)

Both tables carry the standard sync columns (`id` UUID, `seq`, `isArchived`,
`createdAt`, `updatedAt`) so promoting them to synced Convex tables later is
additive, not a rewrite.

- **`savedFilters`** — `id`, `name`, `config` (JSON of the Filter fields above) + sync columns.
- **`dashboardWidgets`** — `id`, `type`, `filterId` (→ savedFilters, nullable for balance-by-account), `position`, `width`, `options` (JSON: title, aggregation, groupBy, limit, chartKind, comparePrevPeriod) + sync columns.

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

## Dependencies to add

- `fl_chart` — breakdown chart (none installed today).
- `ReorderableListView` — built-in, no dep needed.

---

## Phasing

1. **Foundation** — Drift tables + local aggregation queries + layout/flow renderer with a hard-coded default layout (no editing).
2. **Widgets** — implement all four renderers against the aggregations.
3. **Editing** — add / remove / reorder, width control, filter editor + saved-filter management.
4. *(Later)* wire both tables into `SyncEngine` + web parity.
</content>
</invoke>
