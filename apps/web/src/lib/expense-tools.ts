import { api } from '@wallet-bot/backend/api'
import type { ConvexHttpClient } from 'convex/browser'

const MOCK_USER_ID = 'mock-user-demo'

// ── Tool declarations (kept in sync with token constraints in convex/live/actions.ts) ──

export const expenseToolDeclarations = [
    { name: 'addExpense' },
    { name: 'deleteExpense' },
    { name: 'listExpenses' },
    { name: 'getExpenseSummary' },
]

export const EXPENSE_SYSTEM_INSTRUCTION =
    'You are a personal expense tracking assistant. Help the user track their spending by adding expenses, listing recent expenses, deleting expenses, and summarizing their spending. When the user mentions spending money, use the addExpense tool. When they ask about their expenses, use listExpenses or getExpenseSummary as appropriate. When they ask to delete an expense, use deleteExpense. Always confirm after adding or deleting an expense. The user can track expenses in USD (US dollars) or ARS (Argentine pesos). Default to USD unless the user says pesos or ARS. Always include the currency when confirming.'

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
    convexClient: ConvexHttpClient,
    name: string,
    args: ToolCallArgs,
): Promise<Record<string, unknown>> {
    switch (name) {
        case 'addExpense': {
            const currency = args.currency ?? 'USD'
            const id = await convexClient.mutation(
                api.expenses.mutations.addExpense,
                {
                    userId: MOCK_USER_ID,
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
        case 'deleteExpense': {
            await convexClient.mutation(api.expenses.mutations.deleteExpense, {
                userId: MOCK_USER_ID,
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
                    userId: MOCK_USER_ID,
                    startDate: args.startDate ?? '2000-01-01',
                    endDate: args.endDate ?? '2099-12-31',
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
                    userId: MOCK_USER_ID,
                    startDate: args.startDate ?? undefined,
                    endDate: args.endDate ?? undefined,
                },
            )
            return summary
        }
        default:
            return { error: `Unknown tool: ${name}` }
    }
}
