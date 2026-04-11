# Implementation Plan — Expense Tracking v2

Full plan to evolve from a single `expenses` table to the data model described in [data-model.md](./data-model.md).

> **Design constraint — i18n readiness:** All user-facing strings (labels, messages, categories, errors) must be isolated behind key-based lookups from the start. We won't wire up a translation library yet, but every string the user sees goes through a central dictionary so adding languages later is a find-and-replace, not a rewrite.

---

## Phase 0 — Foundations

Shared infrastructure that every later phase depends on.

### 0.1 i18n String Keys

- Create `packages/shared/src/i18n/keys.ts` — flat record of `{ key: englishString }` for all user-facing text (buttons, labels, errors, toasts, empty states).
- Create `packages/shared/src/i18n/index.ts` — `t(key)` function that looks up from the current dictionary. For now it returns the English value. The API is: `t('expenses.add.title')` -> `"Add Expense"`.
- Frontend imports `t()` everywhere instead of hardcoding strings.
- Backend error messages use string keys too (returned to client, displayed via toast).
- **No i18n library dependency yet** — just our own thin abstraction.

### 0.2 Auth Helpers Standardization

- Audit current `authComponent.getAuthUser(ctx)` usage. Create a shared `requireAuth(ctx)` helper in `convex/lib/auth.ts` that throws a typed error if unauthenticated, returns `{ userId, user }`.
- All new features use this helper.

### 0.3 Shared Validators & Types

- Create `convex/lib/validators.ts` for reusable validators (`currencyValidator`, `dateValidator`, `positiveAmount`, etc.).
- These will be shared across all feature schemas and mutations.

---

## Phase 1 — Accounts

### 1.1 Schema

**File:** `convex/schema/accounts.ts`

```
accounts:
  userId:     string
  name:       string          # "Cash", "Banco Galicia", "Visa"
  type:       "asset" | "liability"
  icon:       string          # emoji
  isDefault:  boolean
  sortOrder:  number
  currency:   string          # default currency for this account (USD, ARS)

indexes:
  by_userId: [userId]
  by_userId_default: [userId, isDefault]
```

### 1.2 Backend

**Feature dir:** `convex/accounts/`

| File | Functions |
|---|---|
| `queries.ts` | `listAccounts` (by userId, ordered by sortOrder) |
| `mutations.ts` | `createAccount`, `updateAccount`, `deleteAccount`, `setDefaultAccount` |
| `helpers.ts` | `getDefaultAccount(ctx, userId)`, `ensureAccountOwner(ctx, userId, accountId)` |
| `internal.ts` | `seedDefaultAccounts(ctx, userId)` — called on first login |

**Rules:**
- `deleteAccount` fails if the account has transactions (soft-block, not soft-delete).
- `setDefaultAccount` unsets the previous default in one mutation.
- `seedDefaultAccounts` creates: Cash (asset, default), Bank (asset), Credit Card (liability). Each with the user's default currency.

### 1.3 Auto-Seed on Signup

- Hook into the auth flow: after first successful login, check if user has accounts. If not, call `seedDefaultAccounts`.
- Use a Convex trigger or post-auth webhook depending on what better-auth supports.

### 1.4 Frontend — Account Selector

- New component: `AccountSelector` — dropdown showing user's accounts with icon + name. Used in the add-transaction form.
- Account management page/sheet: list accounts, add new, edit, delete, reorder, set default.
- **Route:** `/accounts` or a sheet/dialog accessible from settings.

### 1.5 Voice Integration

- Update Gemini tool declarations to accept optional `accountName` parameter.
- Default to user's default account when not specified.

---

## Phase 2 — Categories (as a Table)

### 2.1 Schema

**File:** `convex/schema/categories.ts`

```
categories:
  userId:     string | null   # null = system default
  name:       string          # i18n key for system defaults, raw string for user-created
  icon:       string          # emoji
  color:      string          # hex color
  parentId:   id | null       # subcategory support (Gmail-tag style)
  isSystem:   boolean
  sortOrder:  number

indexes:
  by_userId: [userId]
  by_system: [isSystem]
```

### 2.2 Backend

**Feature dir:** `convex/categories/`

| File | Functions |
|---|---|
| `queries.ts` | `listCategories` — returns system defaults + user's custom categories, tree-structured |
| `mutations.ts` | `createCategory`, `updateCategory`, `deleteCategory` |
| `helpers.ts` | `resolveCategoryId(ctx, userId, nameOrId)` — finds category by name or ID |
| `internal.ts` | `seedSystemCategories` — run once on deploy (or check on first query) |

**Subcategory rules (Gmail-tag style):**
- Max 1 level of nesting (parent -> children, no grandchildren).
- A transaction can have ONE category. If it's a subcategory, reports can group by parent.
- Deleting a parent category promotes children to top-level.
- Deleting a category with transactions reassigns them to "Other".

### 2.3 Migration

- Seed the 8 system categories with their existing colors/icons.
- Migrate existing `expenses.category` (string) -> `categoryId` (reference). This is a one-time internal mutation that maps each string to the corresponding system category ID.
- Keep the old `category` field temporarily for safety, remove in a later cleanup.

### 2.4 Frontend

- Replace hardcoded category button grid with dynamic list from `listCategories`.
- Category picker component: shows parent categories, tap to expand subcategories.
- Category management: add/edit/delete custom categories. System categories can be hidden but not deleted.
- Colors and icons are user-customizable for all categories.

### 2.5 Voice Integration

- Update tool declarations: category parameter accepts name (matched via `resolveCategoryId`).
- Gemini instruction updated with dynamic category list.

---

## Phase 3 — Transactions (Replaces Expenses)

This is the core migration. The `expenses` table becomes `transactions`.

### 3.1 Schema

**File:** `convex/schema/transactions.ts`

```
transactions:
  userId:         string
  type:           "expense" | "income" | "transfer"
  amount:         number          # cents, always positive
  currency:       string          # ISO 4217
  description:    string
  categoryId:     id | null       # null for transfers
  tags:           string[]        # tag IDs
  fromAccountId:  id | null       # source (expense, transfer)
  toAccountId:    id | null       # destination (income, transfer)
  date:           string          # YYYY-MM-DD
  notes:          string | null
  recurrenceRule: string | null   # Phase 6

indexes:
  by_userId:              [userId]
  by_userId_date:         [userId, date]
  by_userId_type:         [userId, type]
  by_userId_category:     [userId, categoryId]
  by_userId_account:      [userId, fromAccountId]
  by_userId_toAccount:    [userId, toAccountId]
```

### 3.2 Backend

**Feature dir:** `convex/transactions/`

| File | Functions |
|---|---|
| `queries.ts` | `listTransactions` (paginated, filterable by type/category/account/dateRange/tags), `getTransactionSummary`, `getAccountBalance` |
| `mutations.ts` | `addTransaction`, `updateTransaction`, `deleteTransaction` |
| `helpers.ts` | `validateTransaction(data)` — type-specific validation (expense needs fromAccountId, income needs toAccountId, transfer needs both) |
| `internal.ts` | `migrateExpensesToTransactions` — one-time migration |

**Validation rules by type:**

| Type | fromAccountId | toAccountId | categoryId |
|---|---|---|---|
| `expense` | required | null | required |
| `income` | null | required | optional |
| `transfer` | required | required | null |

**Balance computation:**
```
balance(accountId) =
  SUM(amount) where toAccountId = accountId
  - SUM(amount) where fromAccountId = accountId
```

For liability accounts, negate the display (positive balance = debt).

### 3.3 Migration

1. Add `transactions` table to schema alongside `expenses`.
2. Run `migrateExpensesToTransactions`: for each expense, create a transaction with `type: "expense"`, `fromAccountId: user's default account`, `categoryId: mapped from string`.
3. Update all frontend queries to read from `transactions`.
4. Update voice tools to use transaction mutations.
5. Remove old `expenses` table and feature dir.

### 3.4 Frontend

**New/updated pages:**

| Page/Component | Purpose |
|---|---|
| Transaction list | Replaces expense list. Shows type icon (arrow-down=expense, arrow-up=income, arrows=transfer), amount, category, account, date |
| Add transaction sheet | Tabs or segmented control for expense/income/transfer. Form adapts fields per type. Smart defaults pre-fill account, category, date |
| Transaction detail | Tap a transaction to view/edit. Shows all fields including notes and tags |
| Dashboard/Home | Summary cards: total expenses, total income, net flow. Per-account balances. Category breakdown chart |

**Smart defaults in add form:**
- Type: expense (most common)
- Account: user's default
- Date: today
- Currency: account's default currency
- Category: empty (user picks, or AI suggests later)

### 3.5 Voice Integration

- Expand tools: `addTransaction` (with type inference from natural language), `getBalance`, `transfer`.
- "Spent 50 on groceries" -> expense from default account
- "Got paid 3000" -> income to default account
- "Moved 200 from bank to cash" -> transfer
- "What's my credit card balance?" -> `getAccountBalance`

---

## Phase 4 — Tags

### 4.1 Schema

**File:** `convex/schema/tags.ts`

```
tags:
  userId:   string
  name:     string
  color:    string    # hex

indexes:
  by_userId: [userId]
  by_userId_name: [userId, name]
```

### 4.2 Backend

**Feature dir:** `convex/tags/`

| File | Functions |
|---|---|
| `queries.ts` | `listTags`, `getTagUsageCount` |
| `mutations.ts` | `createTag`, `updateTag`, `deleteTag` (removes from all transactions) |
| `helpers.ts` | `resolveTagIds(ctx, userId, names[])` — find or create tags by name |

**Rules:**
- Tags are user-created only (no system defaults).
- Deleting a tag removes its ID from all transactions that reference it.
- `resolveTagIds` enables voice: "tag it as vacation" auto-creates the tag if it doesn't exist.

### 4.3 Frontend

- Tag chips in transaction list and detail view.
- Tag picker in add/edit form: combobox with create-on-type.
- Filter by tag in transaction list.
- Tag management: list all tags with usage count, edit color/name, delete.

### 4.4 Voice Integration

- "Tag last expense as reimbursable"
- "Show all vacation expenses"
- "Add 30 for coffee, tag it work"

---

## Phase 5 — Multi-Currency

### 5.1 Schema Addition

**File:** `convex/schema/currencies.ts`

```
exchangeRates:
  fromCurrency:  string    # "ARS"
  toCurrency:    string    # "USD"
  rate:          number    # e.g., 0.00098 (1 ARS = 0.00098 USD)
  date:          string    # YYYY-MM-DD
  source:        string    # "manual" | "api"

indexes:
  by_pair_date: [fromCurrency, toCurrency, date]
```

**User preference (on user profile or separate settings table):**
```
userSettings:
  userId:           string
  defaultCurrency:  string    # "USD"
  locale:           string    # "en-US" (for future i18n)

indexes:
  by_userId: [userId]
```

### 5.2 Backend

**Feature dir:** `convex/currencies/`

| File | Functions |
|---|---|
| `queries.ts` | `getExchangeRate(from, to, date)`, `listSupportedCurrencies` |
| `actions.ts` | `fetchExchangeRates` — calls external API, stores in `exchangeRates` table |
| `helpers.ts` | `convertAmount(amount, fromCurrency, toCurrency, date)` — uses latest rate for that date |
| `internal.ts` | `scheduledRateFetch` — daily cron to update rates |

**Rules:**
- Transactions always store the original currency and amount. Never convert on write.
- Conversion happens at query/display time using the rate for that date.
- Summaries let user pick a "display currency" — all amounts converted for aggregation.
- If no rate exists for a specific date, use the closest available rate.

### 5.3 Frontend

- Currency picker in add transaction form (defaults to account's currency).
- Display currency toggle in dashboard/summary views.
- Amounts show original currency inline, converted amount in parentheses if different from display currency.
- User settings: set default currency.

### 5.4 Supported Currencies (Start Small)

Start with: `USD`, `ARS`, `EUR`, `BRL`. Add more as needed. Each has a display symbol, name (i18n key), and decimal places.

---

## Phase 6 — Recurring Transactions

### 6.1 Schema Addition

**File:** `convex/schema/recurrences.ts`

```
recurrences:
  userId:         string
  transactionTemplate:  object    # all transaction fields except date
  frequency:      "daily" | "weekly" | "monthly" | "yearly"
  interval:       number          # every N frequency units
  startDate:      string
  endDate:        string | null   # null = forever
  lastGeneratedDate: string | null
  isActive:       boolean

indexes:
  by_userId: [userId]
  by_active: [isActive, lastGeneratedDate]
```

### 6.2 Backend

- **Cron job:** runs daily, queries active recurrences where `lastGeneratedDate < today`, generates transactions for each missed date, updates `lastGeneratedDate`.
- Use **Convex Workflows** for the generation process (multiple steps, durable).
- `createRecurrence`, `updateRecurrence`, `pauseRecurrence`, `deleteRecurrence` mutations.

### 6.3 Frontend

- "Make recurring" toggle in add/edit transaction form.
- Recurring transactions list in settings.
- Visual indicator on transactions that were auto-generated.

---

## Implementation Order & Dependencies

```
Phase 0: Foundations
  ├── 0.1 i18n keys
  ├── 0.2 Auth helpers
  └── 0.3 Shared validators
          │
Phase 1: Accounts ─────────────────────┐
          │                             │
Phase 2: Categories ───────────────────┤
          │                             │
Phase 3: Transactions (depends on 1+2) ┘
          │
    ┌─────┴─────┐
Phase 4: Tags   Phase 5: Multi-Currency
    └─────┬─────┘
          │
Phase 6: Recurring Transactions
```

**Phases 1 and 2 can be built in parallel** — they have no dependency on each other. Phase 3 depends on both. Phases 4 and 5 can be built in parallel after Phase 3. Phase 6 comes last.

---

## Migration Strategy (Zero Downtime)

Each phase follows the **widen-migrate-narrow** pattern:

1. **Widen:** Add new table/fields alongside old ones. Both work.
2. **Migrate:** Backfill data from old to new.
3. **Narrow:** Remove old table/fields once everything reads from new.

For Phase 3 specifically:
1. Deploy `transactions` table + new mutations/queries.
2. Run migration: convert all `expenses` rows to `transactions`.
3. Update frontend to use new queries.
4. Update voice tools.
5. Remove `expenses` table, feature dir, old constants.

---

## Voice Integration Summary

All voice tool changes across phases:

| Phase | New/Updated Tools |
|---|---|
| 1 | `addTransaction` gets optional `accountName` param |
| 2 | Category matching by name (fuzzy, via `resolveCategoryId`) |
| 3 | `addTransaction` (expense/income/transfer), `getBalance`, `transfer` |
| 4 | `tagTransaction`, filter by tag in list |
| 5 | Currency in natural speech ("50 pesos", "30 dollars") |
| 6 | "Add rent as monthly recurring expense" |

---

## i18n Readiness Checklist

Applied in every phase:

- [ ] All UI strings go through `t(key)` — no hardcoded text in components
- [ ] All backend error messages use string keys
- [ ] Category names (system defaults) stored as i18n keys, resolved on the client
- [ ] Currency names and symbols from a central dictionary
- [ ] Date formatting uses locale-aware formatters (Intl.DateTimeFormat)
- [ ] Number/currency formatting uses Intl.NumberFormat
- [ ] Voice system instruction is a template that can be swapped per locale (future)

---

## Files Changed Per Phase (Estimated)

| Phase | New Files | Modified Files |
|---|---|---|
| 0 | ~3 (i18n, auth helper, validators) | ~5 (existing mutations/queries adopt helpers) |
| 1 | ~5 (schema, queries, mutations, helpers, frontend) | ~3 (schema.ts, signup flow, home page) |
| 2 | ~5 (schema, queries, mutations, helpers, frontend) | ~4 (schema.ts, migration, expense form, voice tools) |
| 3 | ~6 (schema, queries, mutations, helpers, frontend pages) | ~8 (schema.ts, home page rewrite, voice tools, migration) |
| 4 | ~4 (schema, queries, mutations, frontend) | ~4 (transaction form, list, voice tools, schema.ts) |
| 5 | ~5 (schema, queries, actions, helpers, frontend) | ~6 (transaction form, summary views, settings, voice) |
| 6 | ~4 (schema, cron, mutations, frontend) | ~4 (transaction form, settings page, schema.ts) |
