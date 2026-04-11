import { api } from '@wallet-bot/backend/api'
import type { ConvexClient } from 'convex/browser'
import type { ConvexReactClient } from 'convex/react'

type ConvexClientLike = ConvexClient | ConvexReactClient

// ── Tool declarations (kept in sync with token constraints in convex/live/actions.ts) ──

export const expenseToolDeclarations = [
    { name: 'addExpense' },
    { name: 'updateExpense' },
    { name: 'deleteExpense' },
    { name: 'listExpenses' },
    { name: 'getExpenseSummary' },
]

export const EXPENSE_SYSTEM_INSTRUCTION = `You are a personal expense tracking assistant. You help the user manage their expenses through voice.

CAPABILITIES — you can:
• Add new expenses (addExpense)
• Edit existing expenses — change amount, description, category, currency, or date (updateExpense). Always list expenses first to get the ID.
• Delete expenses (deleteExpense). Always list expenses first to get the ID.
• List expenses with optional date range and/or category filter (listExpenses)
• Get a spending summary with totals and category breakdown, optionally filtered by date range and/or category (getExpenseSummary)

CATEGORIES: groceries, transport, dining, entertainment, utilities, health, shopping, other.

CURRENCIES: USD (US dollars) or ARS (Argentine pesos). Default to USD unless the user says "pesos" or "ARS".

RULES:
• When the user mentions spending money, add the expense immediately.
• When the user asks to see, find, or search expenses, use listExpenses. Use the category and date filters when the user specifies them (e.g. "show me dining expenses from last week").
• When the user asks "how much did I spend on X", use getExpenseSummary with the appropriate category/date filters.
• For edit or delete operations, call listExpenses first so you have the expense ID, then call updateExpense or deleteExpense.
• Always confirm after adding, editing, or deleting an expense. Include the amount with currency.
• Keep responses short and conversational.`

// ── Tool execution ─────────────────────────────────────────────

interface ToolCallArgs {
    amount?: number
    currency?: string
    description?: string
    category?: string
    date?: string
    startDate?: string
    endDate?: string
    expenseId?: string
}

function formatAmount(cents: number, currency: string): string {
    const value = (cents / 100).toFixed(2)
    return currency === 'ARS' ? `ARS $${value}` : `USD $${value}`
}

export async function executeToolCall(
    convexClient: ConvexClientLike,
    name: string,
    args: ToolCallArgs,
): Promise<Record<string, unknown>> {
    switch (name) {
        case 'addExpense': {
            const currency = args.currency ?? 'USD'
            const id = await convexClient.mutation(
                api.expenses.mutations.addExpense,
                {
                    amount: Math.round((args.amount ?? 0) * 100),
                    currency,
                    description: args.description ?? '',
                    category: args.category ?? 'other',
                    date: args.date ?? undefined,
                },
            )
            return {
                success: true,
                expenseId: id,
                message: `Expense of ${formatAmount(Math.round((args.amount ?? 0) * 100), currency)} for "${args.description}" added successfully`,
            }
        }
        case 'updateExpense': {
            const updates: Record<string, string | number | undefined> = {}
            if (args.amount !== undefined)
                updates.amount = Math.round(args.amount * 100)
            if (args.currency !== undefined) updates.currency = args.currency
            if (args.description !== undefined)
                updates.description = args.description
            if (args.category !== undefined) updates.category = args.category
            if (args.date !== undefined) updates.date = args.date

            await convexClient.mutation(api.expenses.mutations.updateExpense, {
                expenseId: args.expenseId ?? '',
                ...updates,
            })
            return {
                success: true,
                message: 'Expense updated successfully',
            }
        }
        case 'deleteExpense': {
            await convexClient.mutation(api.expenses.mutations.deleteExpense, {
                expenseId: args.expenseId ?? '',
            })
            return {
                success: true,
                message: 'Expense deleted successfully',
            }
        }
        case 'listExpenses': {
            const expenses = await convexClient.query(
                api.expenses.queries.listExpensesByDateRange,
                {
                    startDate: args.startDate ?? '2000-01-01',
                    endDate: args.endDate ?? '2099-12-31',
                    category: args.category ?? undefined,
                },
            )
            return {
                expenses: expenses.map((e) => ({
                    id: e._id,
                    description: e.description,
                    amount: formatAmount(e.amount, e.currency),
                    currency: e.currency,
                    category: e.category,
                    date: e.date,
                })),
                count: expenses.length,
            }
        }
        case 'getExpenseSummary': {
            const summary = await convexClient.query(
                api.expenses.queries.getExpenseSummary,
                {
                    startDate: args.startDate ?? undefined,
                    endDate: args.endDate ?? undefined,
                    category: args.category ?? undefined,
                },
            )
            return summary
        }
        default:
            return { error: `Unknown tool: ${name}` }
    }
}
