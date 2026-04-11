import { v } from 'convex/values'
import { mutation } from '../_generated/server'
import { authComponent } from '../auth'
import { DEFAULT_CURRENCY } from './constants'
import { todayDateString, validateCategory } from './helpers'

export const addExpense = mutation({
    args: {
        amount: v.number(),
        currency: v.optional(v.string()),
        description: v.string(),
        category: v.string(),
        date: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const user = await authComponent.getAuthUser(ctx)
        if (args.amount <= 0) throw new Error('amount must be positive')

        const category = validateCategory(args.category)

        return await ctx.db.insert('expenses', {
            userId: user._id,
            amount: args.amount,
            currency: args.currency ?? DEFAULT_CURRENCY,
            description: args.description.trim(),
            category,
            date: args.date ?? todayDateString(),
        })
    },
})

export const updateExpense = mutation({
    args: {
        expenseId: v.string(),
        amount: v.optional(v.number()),
        currency: v.optional(v.string()),
        description: v.optional(v.string()),
        category: v.optional(v.string()),
        date: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const user = await authComponent.getAuthUser(ctx)

        const id = ctx.db.normalizeId('expenses', args.expenseId)
        if (!id) throw new Error('Invalid expense ID')

        const expense = await ctx.db.get(id)
        if (!expense) throw new Error('Expense not found')
        if (expense.userId !== user._id) throw new Error('Not authorized')

        const updates: Record<string, string | number> = {}
        if (args.amount !== undefined) {
            if (args.amount <= 0) throw new Error('amount must be positive')
            updates.amount = args.amount
        }
        if (args.currency !== undefined) updates.currency = args.currency
        if (args.description !== undefined)
            updates.description = args.description.trim()
        if (args.category !== undefined)
            updates.category = validateCategory(args.category)
        if (args.date !== undefined) updates.date = args.date

        await ctx.db.patch(id, updates)
    },
})

export const deleteExpense = mutation({
    args: {
        expenseId: v.string(),
    },
    handler: async (ctx, args) => {
        const user = await authComponent.getAuthUser(ctx)

        const id = ctx.db.normalizeId('expenses', args.expenseId)
        if (!id) throw new Error('Invalid expense ID')

        const expense = await ctx.db.get(id)
        if (!expense) throw new Error('Expense not found')
        if (expense.userId !== user._id) throw new Error('Not authorized')

        await ctx.db.delete(id)
    },
})
