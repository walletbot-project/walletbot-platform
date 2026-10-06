import type { z } from 'zod'
import { toolSchemas } from './definitions'
import type { ToolDefinition } from './helpers'
import { zodToToolSchema } from './helpers'

export { AGENT_MODEL, AGENT_VOICE_NAME } from './constants'
export { toolSchemas } from './definitions'

// The `recurringExpense` flag reaches *inside* these tools rather than gating
// them whole: an expense is still an expense with the feature off, but the
// arguments that create or scope a series must not be declared, or the model
// can build a series the user has no UI to see or manage. `withoutRecurrence`
// cuts both the arguments and the sentence documenting them; the descriptions
// below are composed from these suffixes so the two can never drift.
const RECURRENCE_PARTS: Record<
    string,
    { args: readonly string[]; suffix: string }
> = {
    addExpense: {
        args: ['recurrence'],
        suffix: ' Pass `recurrence` to make it repeat — the whole series is created up front as future movements, and the result reports how many and through when.',
    },
    addIncome: {
        args: ['recurrence'],
        suffix: ' Pass `recurrence` to make it repeat, same as addExpense.',
    },
    updateTransaction: {
        args: ['scope', 'recurrence'],
        suffix: ' For an occurrence of a recurring series, `scope` decides whether the edit stops at this movement or carries to every later one — ask the user which, and pass `recurrence` with scope all-future to change the cadence from here on.',
    },
    deleteTransaction: {
        args: ['scope'],
        suffix: ' For an occurrence of a recurring series, `scope` decides whether this deletes one movement or this one and every later one (which also stops the rule there) — ask the user which before calling.',
    },
}

// Tool descriptions. Rules: platform-neutral (every tool behaves identically
// on the native app and on the web app), state defaults, and state the error
// contract where it is not the plain `{ ok: false, error }` envelope.

const toolDescriptions = {
    // Accounts
    listAccounts:
        'List the user accounts. Returns id, name, currency, color, icon, isArchived. Excludes archived accounts unless includeArchived is true.',
    getAccount:
        'Get a single account by UUID or name (case-insensitive). Use it when the context snapshot may be stale or a name is ambiguous — on ambiguity it returns candidates to choose from.',
    getAccountBalance:
        'Get the balance of an account in its own currency: the current one, or with `date` the balance at the end of that day (every movement of the day counts; for today it is the current balance; for a future day it includes the movements already scheduled up to then). For a currency total, call it per account and add the results. Fails with "Account not found" when the id or name resolves to nothing.',
    createAccount:
        'Create a new account. Currency is immutable once set and defaults to the user default currency when omitted. Returns the new account id.',
    updateAccount:
        'Update an account name, description, color or icon. Currency cannot be changed; create a new account instead.',
    archiveAccount:
        'Archive an account (soft delete; there is no in-app restore yet). Its transactions remain.',

    // Categories
    listCategories:
        'List the user categories (id, name, description, color, icon). Excludes archived categories unless includeArchived is true.',
    getCategory:
        'Get a category by UUID or name (case-insensitive). Use it when the context snapshot may be stale or a name is ambiguous — on ambiguity it returns candidates.',
    createCategory:
        'Create a category. Categories are type-agnostic — they classify both expenses and income. Returns the new category id.',
    updateCategory: 'Update a category name, description, color or icon.',
    archiveCategory:
        'Archive a category (soft delete; there is no in-app restore yet). Its transactions remain.',

    // Tags
    listTags:
        'List the user tags (id, name, parentId, color). Tags can form a hierarchy via parent. Excludes archived tags unless includeArchived is true.',
    getTag: 'Get a tag by UUID or name (case-insensitive). Use it when the context snapshot may be stale or a name is ambiguous.',
    createTag:
        'Create a reusable tag, optionally nested under a parent tag. Returns the new tag id.',
    updateTag: 'Update a tag name, description, parent or color.',
    archiveTag:
        'Archive a tag (soft delete). Child tags are re-parented to the archived tag parent.',

    // Transactions: read
    listTransactions:
        'List transactions, newest first, with optional filters: type, account, category, tag, status, date range. With no filters it returns the 10 most recent movements; with filters the default limit is 50.',
    getTransaction:
        'Get a single transaction by id, including its tagIds and, when it belongs to a recurring series, that series (cadence, its position in it, and how far the series reaches). Fails with "Transaction not found" for unknown ids.',
    listUpcomingTransactions:
        'List the movements that exist but have NOT happened yet, soonest first — the other side of Activity. These are excluded from listTransactions, balances and summaries until their date arrives, so this is the only way to see them. Use it for "what do I have coming up?". Includes both occurrences of recurring rules and one-off movements dated in the future.',
    listRecurrences:
        'List the user recurring rules: id, the name of the movements they create, amount, cadence, end date, and how far the series currently reaches. Call it before addRecurrenceOccurrences (which needs a rule id) and to answer "what do I have set to repeat?".',

    // Transactions: write
    addExpense: `Record an expense (money out). Subtracts from the account balance. Requires account + category; the currency comes from the account.${RECURRENCE_PARTS.addExpense.suffix}`,
    addIncome: `Record an income (money in). Adds to the account balance. Requires account + category; the currency comes from the account.${RECURRENCE_PARTS.addIncome.suffix}`,
    addTransfer:
        'Record a transfer between two of the user accounts. Category is optional. For cross-currency transfers, provide toAmount (and optionally exchangeRate) — same-currency transfers derive toAmount automatically.',
    addBalanceAdjustment:
        "Record the user's declaration that an account holds balanceAfter at a moment (now unless date/time say otherwise). Use when the user counted cash or reconciles a statement. The system stores the difference from the balance it had computed just before that moment and keeps it current: recording, editing or deleting a movement dated before the adjustment changes the difference so the declared balance still holds; movements dated after it never touch it.",
    updateTransaction: `Update a transaction: name, description, date/time, amount, category, status, and tags (addTagIdsOrNames / removeTagIdsOrNames apply atomically with the rest of the edit). Unknown tag names are skipped and reported in \`missing\`. A balance adjustment only accepts name, description, status and tags: its amount is derived and its date is when the declaration was made, so to correct a declared balance record a new balance adjustment.${RECURRENCE_PARTS.updateTransaction.suffix}`,
    deleteTransaction: `Delete a transaction. It is archived (soft delete; there is no in-app restore yet) and balances update accordingly. Idempotent: deleting an unknown id still reports ok.${RECURRENCE_PARTS.deleteTransaction.suffix}`,
    addRecurrenceOccurrences:
        'Extend an open-ended recurring rule by another batch, continuing from the LAST occurrence that exists — not from whichever one the user mentioned. Returns how many were created. Fails for a rule with an end date: that series is already complete, so change the end date instead.',

    // Summaries
    summarizeTransactions:
        'Aggregate transactions over a date range. groupBy category returns totals per category (transfers excluded; pass currency to keep the totals in one currency). groupBy account returns per-account money-in, money-out and net, each in the account currency.',

    // Dashboard saved filters
    listSavedFilters:
        'List the saved transaction filters used by home dashboard widgets (shared across the user devices). Returns each canonical filter JSON.',
    createSavedFilter:
        'Create a reusable saved transaction filter from canonical filter JSON. Filter amount values are stored in cents.',
    updateSavedFilter:
        'Update a saved transaction filter name and/or canonical filter JSON. Fails with "Saved filter not found" for unknown or archived ids.',
    archiveSavedFilter:
        'Archive a saved transaction filter. Widgets that referenced it fall back to all transactions.',

    // Home dashboard widgets
    listDashboardWidgets:
        'List the home dashboard widgets in display order, including type, width, options, and resolved filter JSON. The same dashboard is shared across the user devices. Always call this before editing the layout — never invent widget ids.',
    createDashboardWidget:
        'Create a home dashboard widget. Types: stat (aggregation sum/net/count over a filter), list (recent matching movements, `limit` rows), balance (as-of-now balance for `currency`, optionally scoped to accountIds — never date-bounded and it takes no filter), chart (breakdown by category/account/month; transfers are excluded from breakdowns), balance_comparison (the closing balance of last month — every movement of its last day counts —, the current balance, and the difference, for `currency` optionally scoped to accountIds; takes no filter). Width maps to a 6-unit grid: full=6, two_thirds=4, half=3, third=2. New widgets land on a fresh row below everything placed.',
    updateDashboardWidget:
        'Edit a home dashboard widget: type, title, width, filter JSON, display options, background. Options not mentioned keep their current value, except balance and balance_comparison accountIds, which must be re-stated on every edit. Fails with "Dashboard widget not found" for unknown or archived ids.',
    reorderDashboardWidgets:
        'Reorder the home dashboard by passing ALL live widget ids in display order (get them from listDashboardWidgets). Ids that name no live widget are skipped without shifting the rest.',
    archiveDashboardWidget:
        'Archive (remove) a home dashboard widget. Its saved filter is kept.',

    // Agent memory
    addMemory:
        'Save one durable user preference or fact to your long-term memory (shared across the user devices and injected into future sessions). Rejected with "consolidate first" when the memory set is full — merge or rewrite existing entries instead.',
    updateMemory:
        'Rewrite an existing memory. Also the consolidation primitive: merging two memories is one updateMemory plus one forgetMemory. Fails with "Memory not found" for unknown ids.',
    forgetMemory:
        'Delete a memory (on user request, or because it is obsolete or duplicated). Idempotent: forgetting an unknown id still reports ok.',

    // Settings
    updateSettings:
        'Change user settings: language (this device), theme (this device), defaultCurrency (account-wide). Apply the change immediately, then tell the user what changed and that language/theme only affect this device. The result restates exactly that.',

    // Math & dates
    calculate:
        'Evaluate arithmetic exactly instead of doing mental math — totals, percentages, splits, projections, conversions with a user-provided rate. Runs the steps in order; a step may bind its result to a name for later steps. Returns every step value (the last one is the final result). Purely numeric: no dates, currencies, units, or equation solving. Fails with a clear error on unsupported syntax, unknown names, or a non-finite result such as division by zero.',
    calculateDate:
        'Calendar date math. add/subtract N day/week/month/year (month and year steps clamp to the last day: Jan 31 + 1 month = Feb 28). diff counts whole units between date and otherDate, signed. startOf/endOf week/month/year (weeks run Monday–Sunday). dayOfWeek names the weekday. Dates accept the same ISO or natural-language forms as transaction dates. Returns ISO dates plus the English weekday name — translate it when speaking to the user.',

    // Exchange rates
    getExchangeRate:
        'Look up a market exchange rate between two currencies, and optionally convert an amount at it. Quotes come from the app backend, refreshed periodically; this NEVER converts stored money — balances, summaries and movements always stay in their own account currency. Defaults to the official market; ARS pairs also return `alternatives` with the other Argentine quotes so you can name them without asking again. Always carries `asOf` (and `stale: true` past three days) — mention the date when a quote is stale. Errors: "Unknown currency code: X", "from and to are the same currency", "No exchange rate available for X→Y", and "Exchange rates are unavailable right now" when the device has no snapshot cached. A market quote is never the user\'s own transaction rate: for a real cross-currency transfer, ask what actually arrived.',

    // Skills
    readSkill:
        'Read one of your reference skills by slug (the index is in your instructions). Call it BEFORE answering questions about sync/offline behavior, currencies, filter JSON recipes, date semantics, or privacy/data handling. Unknown slug → { ok: false, availableSlugs }.',
} as const satisfies Record<keyof typeof toolSchemas, string>

// Derived types

export type ToolName = keyof typeof toolSchemas

export type ToolArgs<T extends ToolName> = z.infer<(typeof toolSchemas)[T]>

export type ToolsMap = Record<ToolName, ToolDefinition>

// Serialized definitions (for consumers that need plain objects)

export const TOOL_DEFINITIONS = (Object.keys(toolSchemas) as ToolName[]).map(
    (name) =>
        ({
            name,
            description: toolDescriptions[name],
            parameters: zodToToolSchema(toolSchemas[name]),
        }) satisfies ToolDefinition,
)

/**
 * The same definition with everything the `recurringExpense` flag covers
 * removed — the arguments that create or scope a recurring series, and the
 * sentence documenting them. A definition carrying nothing recurring comes
 * back untouched.
 *
 * Applied by the mint when the flag is off, which is the only place the flag
 * is resolved; the argument names and the text live here, next to the
 * descriptions they are cut from. Tools that exist *only* for the feature
 * (`listRecurrences`, `addRecurrenceOccurrences`) are withheld whole there
 * instead.
 */
export function withoutRecurrence(definition: ToolDefinition): ToolDefinition {
    const part = RECURRENCE_PARTS[definition.name]
    if (part === undefined) return definition
    return {
        name: definition.name,
        description: definition.description.replace(part.suffix, ''),
        parameters: {
            ...definition.parameters,
            properties: Object.fromEntries(
                Object.entries(definition.parameters.properties ?? {}).filter(
                    ([name]) => !part.args.includes(name),
                ),
            ),
            required: definition.parameters.required?.filter(
                (name) => !part.args.includes(name),
            ),
        },
    }
}

export const TOOL_MAP = TOOL_DEFINITIONS.reduce<ToolsMap>((acc, tool) => {
    acc[tool.name as ToolName] = tool
    return acc
}, {} as ToolsMap)

/** Every tool name, in declaration order — the cross-platform manifest. */
export const TOOL_NAMES = Object.keys(toolSchemas) as ToolName[]
