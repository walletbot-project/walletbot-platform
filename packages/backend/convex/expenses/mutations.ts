import { v } from 'convex/values'
import { mutation } from '../_generated/server'
import { DEFAULT_CURRENCY } from './constants'
import { todayDateString, validateCategory } from './helpers'

export const addExpense = mutation({
    args: {
        userId: v.string(),
        amount: v.number(),
        currency: v.optional(v.string()),
        description: v.string(),
        category: v.string(),
        date: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        if (!args.userId) throw new Error('userId is required')
        if (args.amount <= 0) throw new Error('amount must be positive')

        const category = validateCategory(args.category)

        return await ctx.db.insert('expenses', {
            userId: args.userId,
            amount: args.amount,
            currency: args.currency ?? DEFAULT_CURRENCY,
            description: args.description.trim(),
            category,
            date: args.date ?? todayDateString(),
        })
    },
})

export const deleteExpense = mutation({
    args: {
        userId: v.string(),
        expenseId: v.string(),
    },
    handler: async (ctx, args) => {
        if (!args.userId) throw new Error('userId is required')

        const id = ctx.db.normalizeId('expenses', args.expenseId)
        if (!id) throw new Error('Invalid expense ID')

        const expense = await ctx.db.get(id)
        if (!expense) throw new Error('Expense not found')
        if (expense.userId !== args.userId) throw new Error('Not authorized')

        await ctx.db.delete(id)
    },
})
