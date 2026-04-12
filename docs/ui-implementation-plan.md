# UI Implementation Plan

Complete plan to build the frontend for all backend features. The backend is fully implemented; the current web app has only a login page, a legacy expenses card, and a voice assistant on a single home page.

**Stack:** Vite + React 19 + Tailwind v4 + shadcn (base-ui) + Convex + better-auth + TanStack Form + Recharts + Sonner + date-fns + lucide-react

---

## Current State

| What exists | Details |
|---|---|
| Pages | `/login` (Google OAuth), `/` (legacy expenses card + voice), `/*` (404) |
| shadcn components (27) | badge, breadcrumb, button, calendar, card, chart, checkbox, collapsible, combobox, command, dialog, dropdown-menu, form (TanStack wrappers), input, label, popover, resizable, separator, sheet, sidebar, skeleton, sonner, tabs, textarea, tooltip |
| Patterns | `useUser()`/`useAuth()`, `useIsMobile()`, `useQuery()`/`useMutation()` from Convex, `FormField`/`FormActions`/`FormSection` (TanStack Form wrappers, unused), Sidebar component (installed, unused) |
| Missing | App shell, navigation, dashboard, transactions CRUD, accounts CRUD, categories CRUD, tags CRUD, recurrences CRUD, settings page |

---

## Architecture Decisions

1. **Dialog/Sheet adaptive**: `useIsMobile()` determines whether forms open as `Dialog` (desktop) or `Sheet` (mobile). Extract a `ResponsiveDialog` wrapper for this.
2. **Pagination**: Use Convex's `usePaginatedQuery` with "Load more" button pattern.
3. **Forms**: All forms use TanStack Form exclusively via `FormField`/`FormActions`/`FormSection`.
4. **URL filters**: Transaction filters stored in URL search params (`useSearchParams()`).
5. **Currency**: All amounts in cents. `CurrencyInput` converts at boundary. `CurrencyDisplay` formats for display.
6. **i18n**: All strings through `t()` from `@wallet-bot/shared`. System category names stored as i18n keys.
7. **Errors**: Every mutation in try/catch, errors via `toast.error()`.
8. **Loading**: Every query-dependent component shows `Skeleton` while loading. Every list has an empty state.

---

## Phase 1 -- Foundational Infrastructure

Everything else depends on these pieces.

### 1.1 Formatting utilities

**File:** `apps/web/src/lib/format.ts`

| Export | Purpose |
|---|---|
| `formatCurrency(cents, currency, locale?)` | `Intl.NumberFormat` with proper symbol |
| `formatDate(dateStr, locale?)` | locale-aware date formatting |
| `formatDateRelative(dateStr)` | "Today", "Yesterday", or formatted |
| `txTypeIcon(type)` | `ArrowDownLeft` / `ArrowUpRight` / `ArrowLeftRight` |
| `txTypeColor(type)` | `text-red-600` / `text-green-600` / `text-blue-600` |

### 1.2 Data hooks

Thin wrappers around `useQuery()` that normalize loading states and provide derived data.

| File | Hook | API | Returns |
|---|---|---|---|
| `hooks/use-user-settings.ts` | `useUserSettings()` | `settings.queries.getUserSettings` | `{ settings, isLoading }` |
| `hooks/use-accounts.ts` | `useAccounts()` | `accounts.queries.listAccounts` | `{ accounts, defaultAccount, isLoading }` |
| `hooks/use-categories.ts` | `useCategories()` | `categories.queries.listCategories` | `{ categories, flatCategories, isLoading }` |
| `hooks/use-tags.ts` | `useTags()` | `tags.queries.listTags` | `{ tags, isLoading }` |
| `hooks/use-voice.ts` | `useVoice()` | `live.actions.requestLiveToken` | Extract from current `home.tsx` |

### 1.3 Shared components

All under `apps/web/src/components/shared/`.

| Component | File | Purpose | Key props |
|---|---|---|---|
| `CurrencyDisplay` | `currency-display.tsx` | Format & render cents as currency | `cents`, `currency`, `className?` |
| `AccountSelector` | `account-selector.tsx` | Account picker (Combobox) | `value`, `onChange`, `label?`, `disabled?` |
| `CategoryPicker` | `category-picker.tsx` | Category picker with hierarchy | `value`, `onChange`, `disabled?` |
| `TagSelector` | `tag-selector.tsx` | Multi-select tag picker | `value: string[]`, `onChange`, `disabled?` |
| `DatePickerField` | `date-picker-field.tsx` | Calendar in Popover | `value` (YYYY-MM-DD), `onChange`, `label?` |
| `CurrencyInput` | `currency-input.tsx` | Amount input (dollars<->cents) | `value` (cents), `onChange`, `currency` |
| `CurrencySelector` | `currency-selector.tsx` | Currency code dropdown | `value`, `onChange` |
| `ColorPicker` | `color-picker.tsx` | Preset color grid + hex input | `value`, `onChange` |
| `EmptyState` | `empty-state.tsx` | Centered icon + title + action | `icon`, `title`, `description?`, `action?` |
| `ListSkeleton` | `loading-skeleton.tsx` | N skeleton rows | `count?` |
| `CardSkeleton` | `loading-skeleton.tsx` | Card-shaped skeleton | -- |
| `ConfirmDialog` | `confirm-dialog.tsx` | Destructive action confirmation | `title`, `description`, `onConfirm`, `variant?` |
| `PageHeader` | `page-header.tsx` | Page title + action buttons | `title`, `description?`, `actions?` |
| `ResponsiveDialog` | `responsive-dialog.tsx` | Dialog on desktop, Sheet on mobile | `open`, `onOpenChange`, `title`, `description?`, `children` |

### 1.4 App shell

**`components/layout/app-sidebar.tsx`** -- Sidebar navigation using installed shadcn `Sidebar` components.

Navigation items:

| Label | Icon | Route |
|---|---|---|
| Dashboard | `LayoutDashboard` | `/` |
| Transactions | `ArrowLeftRight` | `/transactions` |
| Accounts | `Wallet` | `/accounts` |
| Categories | `Grid3x3` | `/categories` |
| Tags | `Tag` | `/tags` |
| Recurring | `Repeat` | `/recurrences` |
| Settings | `Settings` | `/settings` |

Footer: user avatar + name + sign-out.

**`components/layout/mobile-nav.tsx`** -- Bottom tab bar (mobile only, hidden on `md+`). 5 tabs: Dashboard, Transactions, Accounts, Categories, Settings.

**`layouts/root-layout.tsx`** (modify existing) -- Wrap in `SidebarProvider` + `AppSidebar` + `SidebarInset` + `MobileNav`. Voice FAB floats above mobile nav.

**`router.tsx`** (modify existing) -- Add all new routes:

```
/                -> dashboard.tsx
/transactions    -> transactions.tsx
/accounts        -> accounts.tsx
/categories      -> categories.tsx
/tags            -> tags.tsx
/recurrences     -> recurrences.tsx
/settings        -> settings.tsx
```

### 1.5 Voice assistant extraction

Extract `useVoice()` hook from `home.tsx` into `hooks/use-voice.ts`.

**`components/shared/voice-fab.tsx`** -- Floating action button in app shell:
- Collapsed: mic icon button (`fixed bottom-20 right-4 md:bottom-6 md:right-6`)
- Expanded/connected: mic level meter, mute toggle, device picker, disconnect button
- Renders as small Card overlay

---

## Phase 2 -- Dashboard

Main landing page. Financial overview at a glance.

**File:** `apps/web/src/pages/dashboard.tsx`

```
DashboardPage
  PageHeader("Dashboard")
  SummaryCards          -- grid of 3
  AccountBalances       -- card with list
  SpendingByCategory   -- chart card
  RecentTransactions   -- card with list
```

### Summary cards

**File:** `components/dashboard/summary-cards.tsx`

3 cards in `grid grid-cols-1 sm:grid-cols-3 gap-4`:

| Card | Color | Icon | API field |
|---|---|---|---|
| Total Expenses (this month) | red | `ArrowDownLeft` | `totalExpenseCents` |
| Total Income (this month) | green | `ArrowUpRight` | `totalIncomeCents` |
| Net Flow | dynamic | `TrendingUp`/`TrendingDown` | `netFlowCents` |

**API:** `getTransactionSummary({ startDate: firstOfMonth, endDate: lastOfMonth })`

Loading: `CardSkeleton` x 3.

### Account balances

**File:** `components/dashboard/account-balances.tsx`

**API:** `getAllAccountBalances()`

Each row: `icon + name + CurrencyDisplay(balance)`. Default account has star badge.

Loading: `ListSkeleton`. Empty: "No accounts" + link to `/accounts`.

### Spending by category

**File:** `components/dashboard/spending-by-category.tsx`

Donut chart (Recharts `PieChart`) from `byCategory` in summary response. Resolves category names via `useCategories()`. Uses `ChartContainer` from `chart.tsx`.

Loading: `Skeleton` circle. Empty: "No expenses this month".

### Recent transactions

**File:** `components/dashboard/recent-transactions.tsx`

**API:** `listTransactions({ paginationOpts: { numItems: 5, cursor: null } })`

Each row: type icon + description + category badge + `CurrencyDisplay` + date. "View all" link to `/transactions`.

Loading: `ListSkeleton count={5}`. Empty: "No transactions yet" + "Add Transaction" button.

---

## Phase 3 -- Transactions (Full CRUD)

The core feature. Most complex phase.

**File:** `apps/web/src/pages/transactions.tsx`

```
TransactionsPage
  PageHeader("Transactions", actions=<AddTransactionButton>)
  TransactionFilters
  TransactionList (paginated)
```

### Filters

**File:** `components/transactions/transaction-filters.tsx`

| Filter | Component | Stored in |
|---|---|---|
| Type | Tabs: All / Expense / Income / Transfer | URL param `type` |
| Date range | Two `DatePickerField` (start + end) | URL params `from`, `to` |
| Category | `CategoryPicker` | URL param `category` |
| Account | `AccountSelector` | URL param `account` |
| Tag | `TagSelector` (single) | URL param `tag` |

"Clear filters" button when any filter active. Mobile: collapsible via `Collapsible`.

### Transaction list

**File:** `components/transactions/transaction-list.tsx`

Uses `usePaginatedQuery(api.transactions.queries.listTransactions, filters, { initialNumItems: 20 })` with "Load more" button.

Loading: `ListSkeleton`. Empty: `EmptyState` with type-specific message.

### Transaction list item

**File:** `components/transactions/transaction-list-item.tsx`

| Left | Right |
|---|---|
| Type icon (colored) + description | `CurrencyDisplay` (colored by type) |
| Category badge + tag dots | Formatted date |
| Transfer: "from -> to" accounts | |

Click opens edit dialog.

### Add/Edit form

**File:** `components/transactions/transaction-form-dialog.tsx` -- Uses `ResponsiveDialog`.

**File:** `components/transactions/transaction-form.tsx` -- TanStack Form.

**Fields by type:**

| Field | Expense | Income | Transfer |
|---|---|---|---|
| Type | Tabs at top | Tabs at top | Tabs at top |
| Amount | `CurrencyInput` (required) | required | required |
| Currency | `CurrencySelector` (default = account currency) | same | same |
| Description | `Input` (required) | required | required |
| From Account | `AccountSelector` (required, default=default) | hidden | required |
| To Account | hidden | `AccountSelector` (required, default=default) | required |
| Category | `CategoryPicker` (optional) | optional | hidden |
| Tags | `TagSelector` (optional) | optional | optional |
| Date | `DatePickerField` (default=today) | same | same |
| Notes | `Textarea` (collapsible) | same | same |
| Dest. Amount | hidden | hidden | shown if currencies differ |
| Dest. Currency | hidden | hidden | shown if currencies differ |

**Smart defaults:** type=expense, date=today, currency=account's default, account=user's default.

**Validation:**
- `amount`: required, > 0
- `description`: required, non-empty after trim
- `fromAccountId`: required for expense/transfer
- `toAccountId`: required for income/transfer
- `fromAccountId !== toAccountId` for transfers
- `destinationAmount` + `destinationCurrency` must be set together

**APIs:**
- Create: `addTransaction` (convert dollars to cents)
- Edit: `updateTransaction` (only changed fields)
- Success: `toast.success()`, close dialog

### Delete

**File:** `components/transactions/delete-transaction-dialog.tsx` -- Uses `ConfirmDialog`.

---

## Phase 4 -- Accounts

**File:** `apps/web/src/pages/accounts.tsx`

```
AccountsPage
  PageHeader("Accounts", actions=<AddAccountButton + SeedDefaultsButton>)
  AccountList
```

### Account list

**File:** `components/accounts/account-list.tsx`

**API:** `listAccounts()` + `getAllAccountBalances()`

### Account list item

**File:** `components/accounts/account-list-item.tsx`

Row: `icon + name + type badge (asset/liability) + default badge + CurrencyDisplay(balance)`

Three-dot menu: Edit, Set as Default, Delete.

### Account form

**File:** `components/accounts/account-form-dialog.tsx` -- Uses `ResponsiveDialog` + TanStack Form.

| Field | Component | Required |
|---|---|---|
| Name | `Input` | yes |
| Type | Segmented: Asset / Liability | yes |
| Icon | Emoji text input | yes |
| Currency | `CurrencySelector` | yes |

**APIs:** `createAccount`, `updateAccount`, `setDefaultAccount`, `deleteAccount`, `seedDefaultAccounts`

**Delete:** `ConfirmDialog`. Catches "has transactions" error -> toast.

### Delete

**File:** `components/accounts/delete-account-dialog.tsx`

---

## Phase 5 -- Categories

**File:** `apps/web/src/pages/categories.tsx`

```
CategoriesPage
  PageHeader("Categories", actions=<AddCategoryButton + SeedButton>)
  CategoryTree
```

### Category tree

**File:** `components/categories/category-tree.tsx`

Hierarchical list using `Collapsible` for parents with children. System categories show lock icon, cannot be deleted.

### Category list item

**File:** `components/categories/category-list-item.tsx`

Row: colored circle + icon + name (system names via `t()`) + system badge. Three-dot menu: Edit, Delete.

### Category form

**File:** `components/categories/category-form-dialog.tsx` -- Uses `ResponsiveDialog` + TanStack Form.

| Field | Component | Required | Notes |
|---|---|---|---|
| Name | `Input` | yes | disabled for system categories |
| Icon | Emoji text input | yes | |
| Color | `ColorPicker` | yes | |
| Parent | Combobox of top-level categories | no | "None" = top-level |

**APIs:** `createCategory`, `updateCategory`, `deleteCategory`, `seedSystemCategories`

**Delete:** Warns "transactions will be reassigned to Other".

### Delete

**File:** `components/categories/delete-category-dialog.tsx`

---

## Phase 6 -- Tags

**File:** `apps/web/src/pages/tags.tsx`

```
TagsPage
  PageHeader("Tags", actions=<AddTagButton>)
  TagList
```

### Tag list

**File:** `components/tags/tag-list.tsx`

Flat list. Each row: colored dot + name. Three-dot menu: Edit, Delete.

### Tag list item

**File:** `components/tags/tag-list-item.tsx`

### Tag form

**File:** `components/tags/tag-form-dialog.tsx` -- Uses `ResponsiveDialog` + TanStack Form.

| Field | Component | Required |
|---|---|---|
| Name | `Input` (auto-lowercase) | yes |
| Color | `ColorPicker` | yes |

**APIs:** `createTag` (catches duplicate), `updateTag`, `deleteTag`

### Delete

**File:** `components/tags/delete-tag-dialog.tsx`

---

## Phase 7 -- Recurrences

**File:** `apps/web/src/pages/recurrences.tsx`

```
RecurrencesPage
  PageHeader("Recurring Transactions", actions=<AddRecurrenceButton>)
  RecurrenceList
```

### Recurrence list

**File:** `components/recurrences/recurrence-list.tsx`

Each row: type icon + description + `CurrencyDisplay` + frequency label ("Every 2 weeks") + active/paused badge. Paused rows are muted/gray.

### Recurrence list item

**File:** `components/recurrences/recurrence-list-item.tsx`

Three-dot menu: Edit, Pause/Resume, Delete.

### Recurrence form

**File:** `components/recurrences/recurrence-form-dialog.tsx` -- Uses `ResponsiveDialog` + TanStack Form.

Same fields as transaction form, plus:

| Field | Component | Required |
|---|---|---|
| Frequency | Select: Daily / Weekly / Monthly / Yearly | yes |
| Interval | Number input (min 1, "Every N {freq}") | yes |
| Start Date | `DatePickerField` | yes |
| End Date | `DatePickerField` ("Never" if empty) | no |

**APIs:** `createRecurrence`, `updateRecurrence` (includes `isActive` toggle), `deleteRecurrence`

### Delete

**File:** `components/recurrences/delete-recurrence-dialog.tsx`

---

## Phase 8 -- Settings

**File:** `apps/web/src/pages/settings.tsx`

```
SettingsPage
  PageHeader("Settings")
  SettingsForm
  DangerZone
```

### Settings form

**File:** `components/settings/settings-form.tsx` -- TanStack Form.

| Field | Component |
|---|---|
| Default Currency | `CurrencySelector` |
| Locale | Select (en-US only for now) |

**API:** `getUserSettings` (read), `updateUserSettings` (write). Auto-save on change or explicit Save button.

### Danger zone

**File:** `components/settings/danger-zone.tsx`

Card with destructive styling. "Sign Out" button via `useAuth().signOut()`.

---

## Phase Order & Dependencies

```
Phase 1: Foundations (format, hooks, shared components, app shell, voice extraction)
  |
  +---> Phase 2: Dashboard
  +---> Phase 3: Transactions (core CRUD)
  +---> Phase 4: Accounts
  +---> Phase 5: Categories (creates ColorPicker)
  |       |
  |       +---> Phase 6: Tags (uses ColorPicker)
  +---> Phase 7: Recurrences (reuses transaction form patterns)
  +---> Phase 8: Settings
```

Phases 2, 3, 4, 5, 8 can run **in parallel** after Phase 1. Phase 6 needs Phase 5's `ColorPicker`. Phase 7 benefits from Phase 3's form patterns.

---

## Complete File Inventory

### New files (~56)

**Lib (1):**
- `apps/web/src/lib/format.ts`

**Hooks (5):**
- `apps/web/src/hooks/use-user-settings.ts`
- `apps/web/src/hooks/use-accounts.ts`
- `apps/web/src/hooks/use-categories.ts`
- `apps/web/src/hooks/use-tags.ts`
- `apps/web/src/hooks/use-voice.ts`

**Shared components (14):**
- `apps/web/src/components/shared/currency-display.tsx`
- `apps/web/src/components/shared/account-selector.tsx`
- `apps/web/src/components/shared/category-picker.tsx`
- `apps/web/src/components/shared/tag-selector.tsx`
- `apps/web/src/components/shared/date-picker-field.tsx`
- `apps/web/src/components/shared/currency-input.tsx`
- `apps/web/src/components/shared/currency-selector.tsx`
- `apps/web/src/components/shared/color-picker.tsx`
- `apps/web/src/components/shared/empty-state.tsx`
- `apps/web/src/components/shared/loading-skeleton.tsx`
- `apps/web/src/components/shared/confirm-dialog.tsx`
- `apps/web/src/components/shared/page-header.tsx`
- `apps/web/src/components/shared/responsive-dialog.tsx`
- `apps/web/src/components/shared/voice-fab.tsx`

**Layout (2):**
- `apps/web/src/components/layout/app-sidebar.tsx`
- `apps/web/src/components/layout/mobile-nav.tsx`

**Dashboard (5):**
- `apps/web/src/pages/dashboard.tsx`
- `apps/web/src/components/dashboard/summary-cards.tsx`
- `apps/web/src/components/dashboard/account-balances.tsx`
- `apps/web/src/components/dashboard/spending-by-category.tsx`
- `apps/web/src/components/dashboard/recent-transactions.tsx`

**Transactions (7):**
- `apps/web/src/pages/transactions.tsx`
- `apps/web/src/components/transactions/transaction-filters.tsx`
- `apps/web/src/components/transactions/transaction-list.tsx`
- `apps/web/src/components/transactions/transaction-list-item.tsx`
- `apps/web/src/components/transactions/transaction-form-dialog.tsx`
- `apps/web/src/components/transactions/transaction-form.tsx`
- `apps/web/src/components/transactions/delete-transaction-dialog.tsx`

**Accounts (4):**
- `apps/web/src/pages/accounts.tsx`
- `apps/web/src/components/accounts/account-list.tsx`
- `apps/web/src/components/accounts/account-list-item.tsx`
- `apps/web/src/components/accounts/account-form-dialog.tsx`
- `apps/web/src/components/accounts/delete-account-dialog.tsx`

**Categories (4):**
- `apps/web/src/pages/categories.tsx`
- `apps/web/src/components/categories/category-tree.tsx`
- `apps/web/src/components/categories/category-list-item.tsx`
- `apps/web/src/components/categories/category-form-dialog.tsx`
- `apps/web/src/components/categories/delete-category-dialog.tsx`

**Tags (4):**
- `apps/web/src/pages/tags.tsx`
- `apps/web/src/components/tags/tag-list.tsx`
- `apps/web/src/components/tags/tag-list-item.tsx`
- `apps/web/src/components/tags/tag-form-dialog.tsx`
- `apps/web/src/components/tags/delete-tag-dialog.tsx`

**Recurrences (4):**
- `apps/web/src/pages/recurrences.tsx`
- `apps/web/src/components/recurrences/recurrence-list.tsx`
- `apps/web/src/components/recurrences/recurrence-list-item.tsx`
- `apps/web/src/components/recurrences/recurrence-form-dialog.tsx`
- `apps/web/src/components/recurrences/delete-recurrence-dialog.tsx`

**Settings (3):**
- `apps/web/src/pages/settings.tsx`
- `apps/web/src/components/settings/settings-form.tsx`
- `apps/web/src/components/settings/danger-zone.tsx`

### Files to modify (4)

- `apps/web/src/router.tsx` -- add all new routes
- `apps/web/src/layouts/root-layout.tsx` -- sidebar + mobile nav + voice FAB
- `apps/web/src/pages/home.tsx` -- remove (replaced by dashboard)
- `packages/shared/src/i18n/keys.ts` -- add missing keys (frequency labels, filter labels, etc.)

---

## Design Patterns (reference)

### List page pattern

```tsx
export function XxxPage() {
  return (
    <>
      <PageHeader title="Xxx" actions={<Button>Add</Button>} />
      <XxxList />
    </>
  )
}
```

### List component pattern

```tsx
function XxxList() {
  const data = useQuery(api.xxx.queries.listXxx, {})
  if (data === undefined) return <ListSkeleton />
  if (data.length === 0) return <EmptyState icon={X} title="No xxx yet" action={...} />
  return data.map(item => <XxxListItem key={item._id} item={item} />)
}
```

### Form dialog pattern

```tsx
function XxxFormDialog({ open, onOpenChange, item }) {
  const create = useMutation(api.xxx.mutations.createXxx)
  const update = useMutation(api.xxx.mutations.updateXxx)
  const isEdit = !!item

  const form = useForm({
    defaultValues: { name: item?.name ?? '', ... },
    onSubmit: async ({ value }) => {
      try {
        isEdit ? await update({ id: item._id, ...value }) : await create(value)
        toast.success(isEdit ? 'Updated' : 'Created')
        onOpenChange(false)
      } catch (err) {
        toast.error(err.message)
      }
    },
  })

  return (
    <ResponsiveDialog open={open} onOpenChange={onOpenChange} title={isEdit ? 'Edit' : 'Add'}>
      <form onSubmit={(e) => { e.preventDefault(); form.handleSubmit() }}>
        <form.Field name="name" children={(field) => (
          <FormField field={field} label="Name">
            <Input value={field.state.value} onChange={e => field.handleChange(e.target.value)} />
          </FormField>
        )} />
        <form.Subscribe selector={s => [s.canSubmit, s.isSubmitting]} children={([canSubmit, isSubmitting]) => (
          <FormActions>
            <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button type="submit" disabled={!canSubmit}>{isSubmitting ? 'Saving...' : 'Save'}</Button>
          </FormActions>
        )} />
      </form>
    </ResponsiveDialog>
  )
}
```

### Delete dialog pattern

```tsx
function DeleteXxxDialog({ open, onOpenChange, item }) {
  const remove = useMutation(api.xxx.mutations.deleteXxx)
  return (
    <ConfirmDialog
      open={open} onOpenChange={onOpenChange}
      title="Delete xxx?" description="This action cannot be undone."
      variant="destructive"
      onConfirm={async () => {
        try { await remove({ id: item._id }); toast.success('Deleted') }
        catch (err) { toast.error(err.message) }
      }}
    />
  )
}
```
