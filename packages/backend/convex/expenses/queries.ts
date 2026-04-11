import { paginationOptsValidator } from 'convex/server'
import { v } from 'convex/values'
import { query } from '../_generated/server'
import { authComponent } from '../auth'

export const listExpenses = query({
    args: {
        paginationOpts: paginationOptsValidator,
    },
    handler: async (ctx, args) => {
        const user = await authComponent.getAuthUser(ctx)

        return await ctx.db
            .query('expenses')
            .withIndex('by_userId', (q) => q.eq('userId', user._id))
            .order('desc')
            .paginate(args.paginationOpts)
    },
})

export const listExpensesByDateRange = query({
    args: {
        startDate: v.string(),
        endDate: v.string(),
        category: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const user = await authComponent.getAuthUser(ctx)

        const results = await ctx.db
            .query('expenses')
            .withIndex('by_userId_date', (q) =>
                q
                    .eq('userId', user._id)
                    .gte('date', args.startDate)
                    .lte('date', args.endDate),
            )
            .order('desc')
            .take(500)

        if (args.category) {
            return results.filter((e) => e.category === args.category)
        }
        return results
    },
})

export const getExpenseSummary = query({
    args: {
        startDate: v.optional(v.string()),
        endDate: v.optional(v.string()),
        category: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const user = await authComponent.getAuthUser(ctx)

        const start = args.startDate ?? '2000-01-01'
        const end = args.endDate ?? '2099-12-31'

        const allExpenses = await ctx.db
            .query('expenses')
            .withIndex('by_userId_date', (q) =>
                q.eq('userId', user._id).gte('date', start).lte('date', end),
            )
            .take(500)

        const expenses = args.category
            ? allExpenses.filter((e) => e.category === args.category)
            : allExpenses

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
