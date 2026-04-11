import { paginationOptsValidator } from 'convex/server'
import { v } from 'convex/values'
import { query } from '../_generated/server'

export const listExpenses = query({
    args: {
        userId: v.string(),
        paginationOpts: paginationOptsValidator,
    },
    handler: async (ctx, args) => {
        if (!args.userId) throw new Error('userId is required')

        return await ctx.db
            .query('expenses')
            .withIndex('by_userId', (q) => q.eq('userId', args.userId))
            .order('desc')
            .paginate(args.paginationOpts)
    },
})

export const listExpensesByDateRange = query({
    args: {
        userId: v.string(),
        startDate: v.string(),
        endDate: v.string(),
    },
    handler: async (ctx, args) => {
        if (!args.userId) throw new Error('userId is required')

        return await ctx.db
            .query('expenses')
            .withIndex('by_userId_date', (q) =>
                q
                    .eq('userId', args.userId)
                    .gte('date', args.startDate)
                    .lte('date', args.endDate),
            )
            .order('desc')
            .take(500)
    },
})

export const getExpenseSummary = query({
    args: {
        userId: v.string(),
        startDate: v.optional(v.string()),
        endDate: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        if (!args.userId) throw new Error('userId is required')

        const start = args.startDate ?? '2000-01-01'
        const end = args.endDate ?? '2099-12-31'

        const expenses = await ctx.db
            .query('expenses')
            .withIndex('by_userId_date', (q) =>
                q.eq('userId', args.userId).gte('date', start).lte('date', end),
            )
            .take(500)

        let totalCents = 0
        const byCategory: Record<string, number> = {}

        for (const expense of expenses) {
            totalCents += expense.amount
            byCategory[expense.category] =
                (byCategory[expense.category] ?? 0) + expense.amount
        }

        return {
            totalAmount: `$${(totalCents / 100).toFixed(2)}`,
            totalCents,
            count: expenses.length,
            byCategory: Object.entries(byCategory).map(([category, cents]) => ({
                category,
                amount: `$${(cents / 100).toFixed(2)}`,
                cents,
            })),
        }
    },
})
