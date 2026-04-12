import { api } from '@wallet-bot/backend/api'
import { safeCalc } from '@wallet-bot/shared'
import type { ConvexClient } from 'convex/browser'
import type { ConvexReactClient } from 'convex/react'
import type { FunctionArgs } from 'convex/server'

type ConvexClientLike = ConvexClient | ConvexReactClient

// ── Tool declarations (kept in sync with tool names in convex/live/actions.ts) ──

export const transactionToolDeclarations = [
    { name: 'addTransaction' },
    { name: 'updateTransaction' },
    { name: 'deleteTransaction' },
    { name: 'listTransactions' },
    { name: 'getTransactionSummary' },
    { name: 'getAccountBalance' },
    { name: 'calculate' },
    { name: 'fetchExchangeRate' },
    { name: 'createAccount' },
    { name: 'listAccounts' },
]

/** @deprecated Use transactionToolDeclarations */
export const expenseToolDeclarations = transactionToolDeclarations

export const EXPENSE_SYSTEM_INSTRUCTION = '' // System instruction is now in the backend token

// ── Types ──────────────────────────────────────────────────────

type AddTxArgs = FunctionArgs<typeof api.transactions.mutations.addTransaction>
type UpdateTxArgs = FunctionArgs<
    typeof api.transactions.mutations.updateTransaction
>
type DeleteTxArgs = FunctionArgs<
    typeof api.transactions.mutations.deleteTransaction
>

interface ToolCallArgs {
    type?: 'expense' | 'income' | 'transfer'
    amount?: number
    currency?: string
    description?: string
    category?: string
    fromAccountName?: string
    toAccountName?: string
    destinationAmount?: number
    destinationCurrency?: string
    date?: string
    tagNames?: string[]
    notes?: string
    startDate?: string
    endDate?: string
    transactionId?: string
    accountName?: string
    expenseId?: string
    // Calculator
    expression?: string
    // Exchange rate
    fromCurrency?: string
    toCurrency?: string
    // Account creation
    name?: string
    icon?: string
}

// ── Helpers ─────────────────────────────────────────────────────

function formatAmount(cents: number, currency: string): string {
    const value = (cents / 100).toFixed(2)
    const symbols: Record<string, string> = {
        USD: '$',
        ARS: 'AR$',
        EUR: '\u20AC',
        BRL: 'R$',
    }
    return `${symbols[currency] ?? currency} ${value}`
}

async function resolveCategoryId(
    convexClient: ConvexClientLike,
    categoryName: string,
): Promise<AddTxArgs['categoryId']> {
    const categories = await convexClient.query(
        api.categories.queries.listCategories,
        {},
    )
    const lower = categoryName.toLowerCase()
    for (const cat of categories) {
        const nameKey = cat.name.split('.').pop()?.toLowerCase()
        if (nameKey === lower || cat.name.toLowerCase() === lower)
            return cat._id
        for (const child of cat.children) {
            const childKey = child.name.split('.').pop()?.toLowerCase()
            if (childKey === lower || child.name.toLowerCase() === lower)
                return child._id
        }
    }
    return undefined
}

async function resolveTagIds(
    convexClient: ConvexClientLike,
    tagNames: string[],
): Promise<NonNullable<AddTxArgs['tags']>> {
    const existingTags = await convexClient.query(api.tags.queries.listTags, {})
    const ids: NonNullable<AddTxArgs['tags']> = []

    for (const name of tagNames) {
        const lower = name.trim().toLowerCase()
        const existing = existingTags.find((t) => t.name === lower)
        if (existing) {
            ids.push(existing._id)
        } else {
            const id = await convexClient.mutation(
                api.tags.mutations.createTag,
                {
                    name: lower,
                    color: '#6b7280',
                },
            )
            ids.push(id)
        }
    }
    return ids
}

// ── Tool execution ─────────────────────────────────────────────

export async function executeToolCall(
    convexClient: ConvexClientLike,
    name: string,
    args: ToolCallArgs,
): Promise<Record<string, unknown>> {
    switch (name) {
        case 'addTransaction': {
            const txType = args.type ?? 'expense'
            const amountCents = Math.round((args.amount ?? 0) * 100)

            // Resolve accounts — auto-seed if none exist
            let accounts = await convexClient.query(
                api.accounts.queries.listAccounts,
                {},
            )
            if (accounts.length === 0) {
                await convexClient.mutation(
                    api.accounts.mutations.seedDefaultAccounts,
                    {},
                )
                accounts = await convexClient.query(
                    api.accounts.queries.listAccounts,
                    {},
                )
            }

            let fromAccountId: AddTxArgs['fromAccountId']
            let toAccountId: AddTxArgs['toAccountId']

            if (args.fromAccountName) {
                const lower = args.fromAccountName.toLowerCase()
                fromAccountId = accounts.find(
                    (a) => a.name.toLowerCase() === lower,
                )?._id
            }
            if (args.toAccountName) {
                const lower = args.toAccountName.toLowerCase()
                toAccountId = accounts.find(
                    (a) => a.name.toLowerCase() === lower,
                )?._id
            }

            // Default account fallback
            const defaultAccount = accounts.find((a) => a.isDefault)
            if (txType === 'expense' && !fromAccountId) {
                fromAccountId = defaultAccount?._id
            }
            if (txType === 'income' && !toAccountId) {
                toAccountId = defaultAccount?._id
            }

            // Infer currency: explicit > primary account's currency > user default
            const primaryAccount =
                txType === 'expense'
                    ? accounts.find((a) => a._id === fromAccountId)
                    : txType === 'income'
                      ? accounts.find((a) => a._id === toAccountId)
                      : accounts.find((a) => a._id === fromAccountId)
            const currency = (args.currency ??
                primaryAccount?.currency ??
                defaultAccount?.currency ??
                'USD') as AddTxArgs['currency']

            const categoryId = args.category
                ? await resolveCategoryId(convexClient, args.category)
                : undefined

            const tags =
                args.tagNames && args.tagNames.length > 0
                    ? await resolveTagIds(convexClient, args.tagNames)
                    : undefined

            // Cross-currency transfer fields
            const destinationAmountCents = args.destinationAmount
                ? Math.round(args.destinationAmount * 100)
                : undefined
            const destinationCurrency = args.destinationCurrency
                ? (args.destinationCurrency as AddTxArgs['destinationCurrency'])
                : undefined

            const mutationArgs: AddTxArgs = {
                type: txType,
                amount: amountCents,
                currency,
                description: args.description ?? '',
                categoryId,
                tags,
                fromAccountId,
                toAccountId,
                destinationAmount: destinationAmountCents,
                destinationCurrency,
                date: args.date,
                notes: args.notes,
            }

            const id = await convexClient.mutation(
                api.transactions.mutations.addTransaction,
                mutationArgs,
            )
            return {
                success: true,
                transactionId: id,
                message: `${txType} of ${formatAmount(amountCents, currency)} for "${args.description}" added successfully`,
            }
        }

        case 'updateTransaction': {
            const transactionId = (args.transactionId ??
                args.expenseId ??
                '') as UpdateTxArgs['transactionId']

            const updateArgs: UpdateTxArgs = {
                transactionId,
                amount:
                    args.amount !== undefined
                        ? Math.round(args.amount * 100)
                        : undefined,
                currency: args.currency as UpdateTxArgs['currency'],
                description: args.description,
                date: args.date,
                notes: args.notes,
                categoryId: args.category
                    ? await resolveCategoryId(convexClient, args.category)
                    : undefined,
                tags: args.tagNames
                    ? await resolveTagIds(convexClient, args.tagNames)
                    : undefined,
            }

            await convexClient.mutation(
                api.transactions.mutations.updateTransaction,
                updateArgs,
            )
            return {
                success: true,
                message: 'Transaction updated successfully',
            }
        }

        case 'deleteTransaction': {
            const transactionId = (args.transactionId ??
                args.expenseId ??
                '') as DeleteTxArgs['transactionId']

            await convexClient.mutation(
                api.transactions.mutations.deleteTransaction,
                { transactionId },
            )
            return {
                success: true,
                message: 'Transaction deleted successfully',
            }
        }

        case 'listTransactions': {
            const result = await convexClient.query(
                api.transactions.queries.listTransactions,
                {
                    paginationOpts: { numItems: 20, cursor: null },
                    type: args.type,
                    startDate: args.startDate,
                    endDate: args.endDate,
                },
            )
            return {
                transactions: result.page.map((t) => ({
                    id: t._id,
                    type: t.type,
                    description: t.description,
                    amount: formatAmount(t.amount, t.currency),
                    currency: t.currency,
                    date: t.date,
                })),
                count: result.page.length,
            }
        }

        case 'getTransactionSummary': {
            const summary = await convexClient.query(
                api.transactions.queries.getTransactionSummary,
                {
                    startDate: args.startDate,
                    endDate: args.endDate,
                },
            )
            return summary
        }

        case 'getAccountBalance': {
            if (!args.accountName) return { error: 'Account name is required' }
            const accounts = await convexClient.query(
                api.accounts.queries.listAccounts,
                {},
            )
            const lower = args.accountName.toLowerCase()
            const account = accounts.find((a) => a.name.toLowerCase() === lower)
            if (!account)
                return { error: `Account "${args.accountName}" not found` }

            const balance = await convexClient.query(
                api.transactions.queries.getAccountBalance,
                { accountId: account._id },
            )
            return {
                account: account.name,
                balance: formatAmount(balance.balanceCents, balance.currency),
                balanceCents: balance.balanceCents,
                currency: balance.currency,
            }
        }

        case 'calculate': {
            if (!args.expression) return { error: 'Expression is required' }
            try {
                const result = safeCalc(args.expression)
                return { result, expression: args.expression }
            } catch {
                return { error: `Could not evaluate: ${args.expression}` }
            }
        }

        case 'fetchExchangeRate': {
            if (!args.fromCurrency || !args.toCurrency) {
                return { error: 'fromCurrency and toCurrency are required' }
            }
            try {
                const result = await convexClient.action(
                    api.currencies.actions.fetchExchangeRate,
                    {
                        fromCurrency:
                            args.fromCurrency as AddTxArgs['currency'],
                        toCurrency: args.toCurrency as AddTxArgs['currency'],
                    },
                )
                return {
                    fromCurrency: args.fromCurrency,
                    toCurrency: args.toCurrency,
                    rate: result.rate,
                    date: result.date,
                }
            } catch {
                return {
                    error: `Could not fetch rate for ${args.fromCurrency} -> ${args.toCurrency}`,
                }
            }
        }

        case 'createAccount': {
            if (!args.name) return { error: 'Account name is required' }
            try {
                const id = await convexClient.mutation(
                    api.accounts.mutations.createAccount,
                    {
                        name: args.name,
                        type: (args.type as 'asset' | 'liability') ?? 'asset',
                        icon: args.icon ?? '💰',
                        currency:
                            (args.currency as AddTxArgs['currency']) ?? 'USD',
                    },
                )
                return {
                    success: true,
                    accountId: id,
                    message: `Account "${args.name}" created successfully`,
                }
            } catch (err) {
                return {
                    error:
                        err instanceof Error
                            ? err.message
                            : 'Failed to create account',
                }
            }
        }

        case 'listAccounts': {
            const allAccounts = await convexClient.query(
                api.accounts.queries.listAccounts,
                {},
            )
            return {
                accounts: allAccounts.map((a) => ({
                    id: a._id,
                    name: a.name,
                    type: a.type,
                    icon: a.icon,
                    currency: a.currency,
                    isDefault: a.isDefault,
                })),
                count: allAccounts.length,
            }
        }

        // Legacy support
        case 'addExpense':
            return executeToolCall(convexClient, 'addTransaction', {
                ...args,
                type: 'expense',
            })
        case 'updateExpense':
            return executeToolCall(convexClient, 'updateTransaction', args)
        case 'deleteExpense':
            return executeToolCall(convexClient, 'deleteTransaction', args)
        case 'listExpenses':
            return executeToolCall(convexClient, 'listTransactions', {
                ...args,
                type: 'expense',
            })
        case 'getExpenseSummary':
            return executeToolCall(convexClient, 'getTransactionSummary', args)

        default:
            return { error: `Unknown tool: ${name}` }
    }
}
