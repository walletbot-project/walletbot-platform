import { v } from 'convex/values'
import { mutation } from '../_generated/server'
import { ensureAccountOwner } from '../accounts/helpers'
import { requireAuth } from '../lib/auth'
import { currencyValidator, transactionTypeValidator } from '../lib/validators'

const frequencyValidator = v.union(
    v.literal('daily'),
    v.literal('weekly'),
    v.literal('monthly'),
    v.literal('yearly'),
)

export const createRecurrence = mutation({
    args: {
        type: transactionTypeValidator,
        amount: v.number(),
        currency: currencyValidator,
        description: v.string(),
        categoryId: v.optional(v.id('categories')),
        tags: v.optional(v.array(v.id('tags'))),
        fromAccountId: v.optional(v.id('accounts')),
        toAccountId: v.optional(v.id('accounts')),
        notes: v.optional(v.string()),
        frequency: frequencyValidator,
        interval: v.number(),
        startDate: v.string(),
        endDate: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)
        if (args.amount <= 0) throw new Error('Amount must be positive')
        if (args.interval < 1) throw new Error('Interval must be at least 1')

        // Verify account ownership
        if (args.fromAccountId) {
            await ensureAccountOwner(ctx, user._id, args.fromAccountId)
        }
        if (args.toAccountId) {
            await ensureAccountOwner(ctx, user._id, args.toAccountId)
        }

        return await ctx.db.insert('recurrences', {
            userId: user._id,
            type: args.type,
            amount: args.amount,
            currency: args.currency,
            description: args.description.trim(),
            categoryId: args.categoryId,
            tags: args.tags ?? [],
            fromAccountId: args.fromAccountId,
            toAccountId: args.toAccountId,
            notes: args.notes,
            frequency: args.frequency,
            interval: args.interval,
            startDate: args.startDate,
            endDate: args.endDate,
            isActive: true,
        })
    },
})

export const updateRecurrence = mutation({
    args: {
        recurrenceId: v.id('recurrences'),
        amount: v.optional(v.number()),
        currency: v.optional(currencyValidator),
        description: v.optional(v.string()),
        categoryId: v.optional(v.id('categories')),
        tags: v.optional(v.array(v.id('tags'))),
        fromAccountId: v.optional(v.id('accounts')),
        toAccountId: v.optional(v.id('accounts')),
        notes: v.optional(v.string()),
        frequency: v.optional(frequencyValidator),
        interval: v.optional(v.number()),
        endDate: v.optional(v.string()),
        isActive: v.optional(v.boolean()),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)
        const recurrence = await ctx.db.get(args.recurrenceId)
        if (!recurrence) throw new Error('Recurrence not found')
        if (recurrence.userId !== user._id) throw new Error('Not authorized')

        if (args.amount !== undefined && args.amount <= 0)
            throw new Error('Amount must be positive')
        if (args.interval !== undefined && args.interval < 1)
            throw new Error('Interval must be at least 1')

        const { recurrenceId, ...updates } = args
        const patch: Record<string, unknown> = {}
        for (const [key, value] of Object.entries(updates)) {
            if (value !== undefined) {
                patch[key] =
                    key === 'description' && typeof value === 'string'
                        ? value.trim()
                        : value
            }
        }

        await ctx.db.patch(recurrenceId, patch)
    },
})

export const deleteRecurrence = mutation({
    args: {
        recurrenceId: v.id('recurrences'),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)
        const recurrence = await ctx.db.get(args.recurrenceId)
        if (!recurrence) throw new Error('Recurrence not found')
        if (recurrence.userId !== user._id) throw new Error('Not authorized')

        await ctx.db.delete(args.recurrenceId)
    },
})
