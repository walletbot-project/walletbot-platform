import type { z } from 'zod'
import { toolSchemas } from './definitions'
import type { ToolDefinition } from './helpers'
import { zodToToolSchema } from './helpers'

export { toolSchemas } from './definitions'

const toolDescriptions = {
    // Accounts
    listAccounts:
        'List user accounts. Returns id, name, currency, color, icon, isArchived.',
    getAccount: 'Get a single account by UUID or name (case-insensitive).',
    getAccountBalance: 'Get the current balance of an account in its currency.',
    createAccount:
        'Create a new account. Currency is immutable once set. Returns the new account id.',
    updateAccount:
        'Update an account. Currency cannot be changed; create a new account instead.',
    archiveAccount: 'Archive an account (soft delete). Transactions remain.',

    // Categories
    listCategories: 'List user categories.',
    getCategory: 'Get a category by UUID or name.',
    createCategory:
        'Create a category. Categories are type-agnostic — they classify both expenses and income.',
    updateCategory: 'Update a category name or description.',
    archiveCategory: 'Archive a category (soft delete).',

    // Tags
    listTags: 'List user tags. Tags can form a hierarchy via parent.',
    getTag: 'Get a tag by UUID or name.',
    createTag: 'Create a reusable tag. Optionally nest under a parent tag.',
    updateTag: 'Update a tag.',
    archiveTag: 'Archive a tag (soft delete).',

    // Transactions: read
    listTransactions:
        'List transactions with optional filters: type, account, category, tag, status, date range.',
    getTransaction: 'Get a single transaction by id including its tags.',
    getRecentTransactions: 'Shortcut: list the N most recent transactions.',

    // Transactions: write
    addExpense:
        'Record an expense (money out). Subtracts from the account balance. Requires account + category.',
    addIncome:
        'Record an income (money in). Adds to the account balance. Requires account + category.',
    addTransfer:
        'Record a transfer between two accounts. For cross-currency transfers, provide toAmount (and optionally exchangeRate).',
    addBalanceAdjustment:
        'Record that the actual balance of an account is balanceAfter. The system computes the difference. Use when the user counted cash or reconciles a statement.',
    updateTransaction:
        "Update a transaction's name, description, date, amount, category, or status.",
    deleteTransaction: 'Delete a transaction. Updates balances accordingly.',
    tagTransaction: 'Attach one or more tags to a transaction.',
    untagTransaction: 'Detach one or more tags from a transaction.',

    // Summaries
    summarizeByCategory:
        'Totals per category over a date range. Optionally filter by transaction type.',
    summarizeByAccount:
        'Per-account balance, money-in and money-out over a date range.',

    // Dashboard saved filters
    listSavedFilters:
        'List saved transaction filters used by native home dashboard widgets. Returns each canonical filter JSON.',
    createSavedFilter:
        'Create a reusable saved transaction filter from canonical filter JSON. Native dashboard feature.',
    updateSavedFilter:
        'Update a saved transaction filter name and/or canonical filter JSON. Native dashboard feature.',
    archiveSavedFilter:
        'Archive a saved transaction filter. Widgets that referenced it will fall back to all transactions.',

    // Home dashboard widgets
    listDashboardWidgets:
        'List native home dashboard widgets in display order, including type, width, options, and resolved filter JSON.',
    createDashboardWidget:
        'Create a native home dashboard widget. Supports stat, list, balance, chart, width, canonical filter JSON, and background options.',
    updateDashboardWidget:
        'Edit a native home dashboard widget. Can change type, title, width, filter JSON, display options, and background.',
    reorderDashboardWidgets:
        'Reorder native home dashboard widgets by passing all widget ids in display order.',
    archiveDashboardWidget: 'Archive/remove a native home dashboard widget.',
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
