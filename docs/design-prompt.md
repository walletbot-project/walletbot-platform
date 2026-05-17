# Design Request — WalletBot

I need you to design the visual identity, UX, and full UI for **WalletBot**, a personal expense tracking app. Below is everything you need to know about the product, its features, and its data model. Use this as the source of truth.

---

## 1. The app

**WalletBot** is a personal finance app for tracking where your money is and where it goes. It is **not** a budgeting app, **not** an accounting tool, and **not** a bank aggregator. It is a fast, explicit, offline-first ledger the user controls manually.

### Product principles

- **Explicit, not magical.** The user records their own movements. No statement scraping, no AI auto-categorization happening behind their back.
- **Simple vocabulary.** Only four concepts are ever shown: Accounts, Categories, Movements, Tags. No "debits," "credits," "journals," "double entry," or accounting jargon.
- **Offline-first.** Every action works without a network. Sync is background and invisible. The native app must function fully offline.
- **Multi-platform.** Native mobile (Flutter) is the primary surface. A web app (React) exists for desktop use. Both share the same data via a Convex backend.
- **Multi-currency.** Each account has a fixed currency. Transfers can cross currencies with an exchange rate.
- **Voice-first capable.** A voice agent can create movements via natural language ("Starbucks, 5 bucks cash"). The UI must accommodate fast manual entry too.

### Platforms to design for

1. **Native mobile** (iOS + Android, Flutter) — primary
2. **Web app** (React + Tailwind v4 + shadcn/base-ui) — secondary, desktop-focused

Design must feel native on each platform but share a coherent visual identity.

---

## 2. The four core concepts

The entire app revolves around these four nouns. The user sees them, names them, and manipulates them directly.

### Account — *where the money lives*

A bucket of money the user owns. Examples: Cash, BBVA, Galicia, Visa, Mercado Pago.

- Each account has a **fixed currency** (cannot change after creation).
- Each account has an optional color and icon (from a predefined set).
- Accounts can be archived (hidden but not deleted, preserves history).
- The current **balance** of each account is computed from its movements and shown prominently.

### Category — *what kind of movement it was*

A classifier for movements. Examples: Food, Transport, Salary, Gifts, Rent.

- Categories are **type-agnostic**: the same "Gifts" category can be used for both expenses (gift given) and income (gift received). The movement's `type` is what determines the direction.
- Categories can have a description and be archived.

### Movement — *the actual transaction*

A single entry in the ledger. Has one of four types:

| Type | Meaning | Effect on balance |
|---|---|---|
| `expense` | Money leaving an account | `-amount` on the account |
| `income` | Money entering an account | `+amount` on the account |
| `transfer` | Money moving between two accounts (same or different currency) | `-amount` on source, `+toAmount` on destination |
| `balance_adjustment` | User correcting a discrepancy (e.g. "I counted cash and there's actually $200") | applies the difference; stores observed `balanceAfter` |

Every movement has: `name`, optional `description`, `date`, `status` (`pending` or `cleared`), `accountId`, `categoryId`, `amount`, `currency`. Transfers add `toAccountId`, `toAmount`, `toCurrency`, optional `exchangeRate`. Balance adjustments add `balanceAfter`.

### Tag — *free-form labels*

Optional, reusable labels attached to movements. Examples: `work`, `vacation-bali-2026`, `reimbursable`, `shared-with-ana`.

- Global per user (any tag can be applied to any movement).
- Have a color.
- Can form an optional **hierarchy** via `parentId` (e.g. `vacations > bali-2026`).
- A movement can have many tags; a tag can be on many movements (N–N).

---

## 3. Features the design must cover

### 3.1 Onboarding
- First-time launch: sign in (Google / email).
- Quick setup: create first account (with currency), seed a few default categories.

### 3.2 Home / Dashboard
- **Total net worth** across all accounts (handling multi-currency display thoughtfully — likely a single "display currency" preference with notes for accounts in other currencies).
- **List of accounts** with current balance per account.
- **Recent movements** feed (chronological).
- **Quick add** floating action: expense / income / transfer / adjustment.

### 3.3 Accounts
- List view (all accounts, archived hidden behind a toggle).
- Detail view: account info, current balance, full movement history filtered to this account, edit/archive actions.
- Create / edit account: name, currency (locked after creation), color, icon, description.

### 3.4 Categories
- List view (with archived toggle).
- Detail view: monthly totals split by `type` (expenses vs. income in this category), recent movements in this category.
- Create / edit category: name, description.

### 3.5 Movements
- **List view** with strong filtering: by date range, account, category, tag, type, status, text search.
- **Movement detail / edit**: type-specific form (expense, income, transfer, adjustment all have slightly different fields — design needs to handle this elegantly).
- **Quick add flows** for each of the four types. The expense flow is the hottest path — it must be one-handed and fast.
- **Pending vs. cleared** status indicator (e.g. credit card transactions awaiting statement).

### 3.6 Tags
- List view with hierarchy display.
- Tag detail: movements with this tag, aggregate totals.
- Create / edit tag: name, color, optional parent, description.
- Tag picker UI within the movement form (multi-select, searchable, create-on-the-fly).

### 3.7 Reports / Insights
- **Spending by category** (per month, per currency, per type).
- **Income vs. expense** trend over time.
- **Account balance** history.
- Tag-based aggregates (future, but reserve space in the IA).

### 3.8 Voice agent
- A conversational entry point ("press and hold to talk") that interprets natural-language descriptions of movements and creates them.
- The design must include the listening / transcribing / confirming states and a way for the user to review and adjust before saving.

### 3.9 Sync indicator
- Subtle but visible indicator that shows: synced / syncing / offline / error.
- Never blocks the user from working — offline is a first-class state, not an error.

### 3.10 Settings
- Profile, sign out.
- Default currency / display currency.
- Theme (light / dark / system).
- Data export.
- Archived items management.

---

## 4. Data model summary (for context, not for surfacing to the user)

The user never sees the schema. But the design must respect what the schema makes possible (and impossible). Key facts:

- All entities are **per-user**, identified by a client-generated **UUID** (`id`). The user never sees these IDs.
- All timestamps are **milliseconds since epoch**, stored as int64.
- All money amounts are **integer cents** (e.g. `550` means $5.50). The UI is responsible for formatting.
- Each account's **currency is fixed**; movement currency must match its account currency. The transfer form must enforce this — the source amount is in the source account's currency, the destination amount is in the destination account's currency, with an explicit exchange rate when they differ.
- **Archival**, not deletion, is the default for user-facing "delete." Hard deletion exists but is rare and only via a deliberate action.
- **Status** on a movement: `pending` (e.g. unposted credit card charge) or `cleared`. Both count toward balance for now, but the UI should visually distinguish them.

### Sync model (relevant for UX)

The app is offline-first with eventual consistency:

- Every write happens locally first and is reflected in the UI immediately.
- A background sync engine pushes changes to the server and pulls remote changes.
- Conflicts are rare (single-user, multi-device) but possible — last-write-wins per row is acceptable; design doesn't need a manual conflict resolution UI for v1.
- A small **sync state badge** somewhere (status bar / header) is enough.

### Entities (technical schema, abridged)

- `accounts` — id, name, currency, color?, icon?, description?, isArchived
- `categories` — id, name, description?, isArchived
- `transactions` — id, type, name, description?, status, date, accountId, amount, currency, categoryId, optional transfer fields (toAccountId, toAmount, toCurrency, exchangeRate), optional balance_adjustment field (balanceAfter), isArchived
- `tags` — id, name, description?, parentId?, color?, isArchived
- `transactionTags` — N–N join (transactionId, tagId)

Full schema is in [data-model.md](./data-model.md) if you want exact field names and indices — but **do not surface technical names to the user**. The user sees "Movement," not "transaction"; "Movement type," not "type enum."

---

## 5. Visual identity goals

I want the design to feel:

- **Calm and trustworthy.** This is people's money — no gamification, no celebratory animations, no nagging.
- **Fast.** Every screen should feel like it loads instantly (it does — offline-first).
- **Latin American friendly.** Most users are Spanish-speaking and used to multi-currency reality (ARS + USD coexisting, exchange rates, informal accounts). The UI must handle this gracefully and not feel like a US-centric app retrofitted.
- **Modern but not trendy.** It should still feel current in 5 years. Avoid stylistic choices that scream "2026."
- **Legible.** Dense lists of numbers must be scannable. Tabular numerals, clear hierarchy.

### What I need from you

1. **Brand**: name treatment / logo, color palette (incl. dark mode), typography.
2. **Native app**: full screen flow for every feature listed in section 3, designed for iOS and Android.
3. **Web app**: desktop-first reinterpretation of the same flows.
4. **Component library**: buttons, inputs, lists, cards, modals, the movement form variants, account/category/tag pickers, charts.
5. **Empty states, loading states, error states, offline states** for every major screen.
6. **Voice agent UI** states.
7. **Iconography** for accounts (a tasteful predefined set), categories, and the four movement types.

---

## 6. Out of scope

- Multi-user / shared wallets.
- Bank integrations / Plaid-style aggregation.
- Investment tracking, crypto portfolios.
- Bill reminders / recurring transactions (future, not v1).
- Budgets and budget limits (future, not v1).

---

## 7. Deliverables format

Whatever works best for your process — Figma file, exported PNGs, or detailed written specs. I will be reviewing on both desktop and mobile, so make sure mobile mockups are viewable at native size.

Ask me anything you need clarified before starting. Especially about: tone of voice, exact target users, competitor references I do or don't want to look like, and any constraints I haven't mentioned.
