import type { z } from 'zod'
import { toolSchemas } from './definitions'
import type { ToolDefinition } from './helpers'
import { zodToToolSchema } from './helpers'

export { AGENT_MODEL, AGENT_VOICE_NAME } from './constants'
export { toolSchemas } from './definitions'

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
        'Get the current balance of an account in its own currency. Fails with "Account not found" when the id or name resolves to nothing.',
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
        'Get a single transaction by id, including its tagIds. Fails with "Transaction not found" for unknown ids.',

    // Transactions: write
    addExpense:
        'Record an expense (money out). Subtracts from the account balance. Requires account + category; the currency comes from the account.',
    addIncome:
        'Record an income (money in). Adds to the account balance. Requires account + category; the currency comes from the account.',
    addTransfer:
        'Record a transfer between two of the user accounts. Category is optional. For cross-currency transfers, provide toAmount (and optionally exchangeRate) — same-currency transfers derive toAmount automatically.',
    addBalanceAdjustment:
        'Record that the actual balance of an account is balanceAfter. The system computes the difference. Use when the user counted cash or reconciles a statement.',
    updateTransaction:
        'Update a transaction: name, description, date/time, amount, category, status, and tags (addTagIdsOrNames / removeTagIdsOrNames apply atomically with the rest of the edit). Unknown tag names are skipped and reported in `missing`.',
    deleteTransaction:
        'Delete a transaction. It is archived (soft delete; there is no in-app restore yet) and balances update accordingly. Idempotent: deleting an unknown id still reports ok.',

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
        'Create a home dashboard widget. Types: stat (aggregation sum/net/count over a filter), list (recent matching movements, `limit` rows), balance (as-of-now balance for `currency`, optionally scoped to accountIds — never date-bounded and it takes no filter), chart (breakdown by category/account/month; transfers are excluded from breakdowns). Width maps to a 6-unit grid: full=6, two_thirds=4, half=3, third=2. New widgets land on a fresh row below everything placed.',
    updateDashboardWidget:
        'Edit a home dashboard widget: type, title, width, filter JSON, display options, background. Options not mentioned keep their current value, except balance accountIds which must be re-stated on every edit. Fails with "Dashboard widget not found" for unknown or archived ids.',
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

export const TOOL_MAP = TOOL_DEFINITIONS.reduce<ToolsMap>((acc, tool) => {
    acc[tool.name as ToolName] = tool
    return acc
}, {} as ToolsMap)

/** Every tool name, in declaration order — the cross-platform manifest. */
export const TOOL_NAMES = Object.keys(toolSchemas) as ToolName[]
