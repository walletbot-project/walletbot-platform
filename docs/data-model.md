# Data & Logic Model — Expense Tracking

## Core Philosophy

The engine is double-entry accounting, but the user never sees it. They just say "I spent $50 on groceries" and the system figures out the rest. Smart defaults minimize friction — most actions require only an amount and a description.

---

## Entities

### 1. Accounts

Every user gets auto-created accounts on signup. Users don't manage these directly — they just pick _where money came from_.

| Field         | Type     | Purpose                                |
| ------------- | -------- | -------------------------------------- |
| `userId`      | string   | Owner                                  |
| `name`        | string   | "Cash", "Bank", "Credit Card"          |
| `type`        | string   | `asset` or `liability`                 |
| `icon`        | string   | Emoji or icon key                      |
| `isDefault`   | boolean  | Which account is pre-selected in forms |
| `sortOrder`   | number   | Display ordering                       |

**Auto-created on signup:** "Cash" (asset), "Bank" (asset), "Credit Card" (liability).

Users can add more accounts but most won't need to. Balances are always computed from transactions — never stored separately.

### 2. Categories

Promoted from hardcoded strings to a user-customizable table.

| Field      | Type            | Purpose                                    |
| ---------- | --------------- | ------------------------------------------ |
| `userId`   | string \| null  | null = system default, string = user-created |
| `name`     | string          | "Groceries", "Transport"...                |
| `icon`     | string          | Emoji                                      |
| `color`    | string          | Hex color for UI badges                    |
| `parentId` | id \| null      | Optional parent for subcategories          |

**System defaults** (same 8 as today): groceries, transport, dining, entertainment, utilities, health, shopping, other.

Subcategories are optional. A flat list works for most people, but the `parentId` field allows power users to organize (e.g., "Food > Groceries", "Food > Dining Out").

### 3. Tags

Cross-cutting, user-created labels. They answer questions categories can't.

| Field    | Type   | Purpose           |
| -------- | ------ | ----------------- |
| `userId` | string | Owner             |
| `name`   | string | "vacation", "reimbursable", "shared" |
| `color`  | string | Hex color for UI  |

Many-to-many relationship with transactions (stored as `string[]` on the transaction).

**Example use cases:**
- "vacation" — tag expenses across different categories during a trip
- "reimbursable" — mark work expenses to claim later
- "shared" — expenses split with someone else

### 4. Transactions

Replaces the current `expenses` table. Each user action creates one transaction record.

| Field            | Type           | Purpose                                     |
| ---------------- | -------------- | ------------------------------------------- |
| `userId`         | string         | Owner                                       |
| `type`           | string         | `expense`, `income`, or `transfer`          |
| `amount`         | number         | In cents (always positive)                  |
| `currency`       | string         | ISO 4217 code (USD, ARS)                    |
| `description`    | string         | "Supermarket", "Salary"...                  |
| `categoryId`     | id \| null     | Reference to Categories (null for transfers) |
| `tags`           | string[]       | Tag IDs                                     |
| `fromAccountId`  | id \| null     | Source account                              |
| `toAccountId`    | id \| null     | Destination account (transfers only)        |
| `date`           | string         | YYYY-MM-DD                                  |
| `notes`          | string \| null | Optional free text                          |
| `recurrenceRule` | string \| null | Optional — for recurring transactions       |

---

## How Double-Entry Works (Invisibly)

The user interacts with three simple concepts. The system maps each to the correct accounting entries.

### Expense — "Spent $50 on groceries"

```
type: "expense"
fromAccountId: <user's default account>
toAccountId: null
categoryId: <groceries>
```

Money leaves the source account. The category tracks what it was spent on.

### Income — "Got paid $3000"

```
type: "income"
fromAccountId: null
toAccountId: <user's bank account>
categoryId: <salary> (optional)
```

Money enters the destination account.

### Transfer — "Moved $500 from bank to cash"

```
type: "transfer"
fromAccountId: <bank>
toAccountId: <cash>
categoryId: null
```

Money moves between accounts. Does not count as income or expense in reports.

### Computing Balances

Account balance = sum of all incoming transactions - sum of all outgoing transactions.

- For `asset` accounts (bank, cash): positive balance = money you have
- For `liability` accounts (credit card): positive balance = money you owe

No stored balance field — always derived from transactions. This guarantees consistency.

---

## UX Principles

### Smart Defaults (Minimize Friction)

Adding an expense should require **only amount + description** in the common case. Everything else is pre-filled:

| Field    | Default                                              |
| -------- | ---------------------------------------------------- |
| Date     | Today                                                |
| Account  | User's default account (or last used)                |
| Category | AI-suggested from description ("Uber" -> transport)  |
| Currency | User's default currency                              |
| Tags     | Empty                                                |
| Notes    | Empty                                                |

### Voice-First Friendly

The existing Gemini Live integration should handle all transaction types:

- "Spent 50 on groceries" -> expense from default account
- "Got paid 3000" -> income to default account
- "Moved 500 from bank to cash" -> transfer
- "Tag last expense as vacation" -> adds tag

### Progressive Disclosure

- **Level 1 (most users):** Amount, description, category. That's it.
- **Level 2 (curious users):** Pick account, add tags, write notes.
- **Level 3 (power users):** Subcategories, multiple accounts, recurring rules.

---

## What This Unlocks

| Feature                | How                                                   |
| ---------------------- | ----------------------------------------------------- |
| Account balances       | "How much is on my credit card?" — sum transactions   |
| Category budgets       | Set monthly limits per category, compare vs. actuals  |
| Tag filtering          | "Show me all 'vacation' expenses"                     |
| Transfers              | Move money between accounts without affecting reports |
| Income tracking        | See net cash flow, not just spending                  |
| Recurring transactions | Rent, subscriptions — auto-created on schedule        |
| Smart categorization   | AI suggests category from description                 |

---

## Migration Path

Incremental steps from current state to full model:

1. **Accounts** — create table, auto-create defaults on signup, migrate existing expenses to reference default account
2. **Categories as a table** — migrate from hardcoded strings, seed system defaults
3. **Transactions** — rename/migrate expenses table, add `type` field (all existing = `expense`), add income + transfer support
4. **Tags** — purely additive, no migration needed
5. **Recurring transactions** — needs a Convex scheduler/cron, build later

---

## Open Questions

- **Subcategories**: Support from day 1 or add later? (Schema supports it via `parentId`, UI can ignore it initially)
- **Multi-currency**: Just track separately, or add exchange rate conversion?
- **Tags**: Day-1 feature or defer to keep initial scope smaller?
- **Budgets**: Part of this model or a separate feature doc?
