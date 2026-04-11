import { v } from 'convex/values'
import { mutation } from '../_generated/server'
import { ensureAccountOwner } from '../accounts/helpers'
import { requireAuth } from '../lib/auth'
import {
    currencyValidator,
    todayDateString,
    transactionTypeValidator,
} from '../lib/validators'
import { validateTransactionShape } from './helpers'

export const addTransaction = mutation({
    args: {
        type: transactionTypeValidator,
        amount: v.number(),
        currency: currencyValidator,
        description: v.string(),
        categoryId: v.optional(v.id('categories')),
        tags: v.optional(v.array(v.id('tags'))),
        fromAccountId: v.optional(v.id('accounts')),
        toAccountId: v.optional(v.id('accounts')),
        // Cross-currency transfers
        destinationAmount: v.optional(v.number()),
        destinationCurrency: v.optional(currencyValidator),
        date: v.optional(v.string()),
        notes: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)
        if (args.amount <= 0) throw new Error('Amount must be positive')
        if (
            args.destinationAmount !== undefined &&
            args.destinationAmount <= 0
        ) {
            throw new Error('Destination amount must be positive')
        }

        // Cross-currency fields must be provided together
        if (args.destinationAmount !== undefined && !args.destinationCurrency) {
            throw new Error(
                'Destination currency is required when destination amount is provided',
            )
        }
        if (
            args.destinationCurrency !== undefined &&
            args.destinationAmount === undefined
        ) {
            throw new Error(
                'Destination amount is required when destination currency is provided',
            )
        }

        validateTransactionShape({
            type: args.type,
            fromAccountId: args.fromAccountId,
            toAccountId: args.toAccountId,
            categoryId: args.categoryId,
        })

        // Verify account ownership
        if (args.fromAccountId) {
            await ensureAccountOwner(ctx, user._id, args.fromAccountId)
        }
        if (args.toAccountId) {
            await ensureAccountOwner(ctx, user._id, args.toAccountId)
        }

        // Verify category exists (if provided)
        if (args.categoryId) {
            const cat = await ctx.db.get(args.categoryId)
            if (!cat) throw new Error('Category not found')
            if (!cat.isSystem && cat.userId !== user._id)
                throw new Error('Not authorized')
        }

        return await ctx.db.insert('transactions', {
            userId: user._id,
            type: args.type,
            amount: args.amount,
            currency: args.currency,
            description: args.description.trim(),
            categoryId: args.categoryId,
            tags: args.tags ?? [],
            fromAccountId: args.fromAccountId,
            toAccountId: args.toAccountId,
            destinationAmount: args.destinationAmount,
            destinationCurrency: args.destinationCurrency,
            date: args.date ?? todayDateString(),
            notes: args.notes,
        })
    },
})

export const updateTransaction = mutation({
    args: {
        transactionId: v.id('transactions'),
        type: v.optional(transactionTypeValidator),
        amount: v.optional(v.number()),
        currency: v.optional(currencyValidator),
        description: v.optional(v.string()),
        categoryId: v.optional(v.id('categories')),
        tags: v.optional(v.array(v.id('tags'))),
        fromAccountId: v.optional(v.id('accounts')),
        toAccountId: v.optional(v.id('accounts')),
        destinationAmount: v.optional(v.number()),
        destinationCurrency: v.optional(currencyValidator),
        date: v.optional(v.string()),
        notes: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)

        const tx = await ctx.db.get(args.transactionId)
        if (!tx) throw new Error('Transaction not found')
        if (tx.userId !== user._id) throw new Error('Not authorized')

        if (args.amount !== undefined && args.amount <= 0) {
            throw new Error('Amount must be positive')
        }
        if (
            args.destinationAmount !== undefined &&
            args.destinationAmount <= 0
        ) {
            throw new Error('Destination amount must be positive')
        }

        // Build the merged state to validate shape
        const merged = {
            type: args.type ?? tx.type,
            fromAccountId: args.fromAccountId ?? tx.fromAccountId,
            toAccountId: args.toAccountId ?? tx.toAccountId,
            categoryId: args.categoryId ?? tx.categoryId,
        }
        validateTransactionShape(merged)

        // Verify account ownership if changing accounts
        if (args.fromAccountId) {
            await ensureAccountOwner(ctx, user._id, args.fromAccountId)
        }
        if (args.toAccountId) {
            await ensureAccountOwner(ctx, user._id, args.toAccountId)
        }

        const { transactionId, ...updates } = args
        const patch: Record<string, unknown> = {}
        if (updates.type !== undefined) patch.type = updates.type
        if (updates.amount !== undefined) patch.amount = updates.amount
        if (updates.currency !== undefined) patch.currency = updates.currency
        if (updates.description !== undefined)
            patch.description = updates.description.trim()
        if (updates.categoryId !== undefined)
            patch.categoryId = updates.categoryId
        if (updates.tags !== undefined) patch.tags = updates.tags
        if (updates.fromAccountId !== undefined)
            patch.fromAccountId = updates.fromAccountId
        if (updates.toAccountId !== undefined)
            patch.toAccountId = updates.toAccountId
        if (updates.destinationAmount !== undefined)
            patch.destinationAmount = updates.destinationAmount
        if (updates.destinationCurrency !== undefined)
            patch.destinationCurrency = updates.destinationCurrency
        if (updates.date !== undefined) patch.date = updates.date
        if (updates.notes !== undefined) patch.notes = updates.notes

        await ctx.db.patch(transactionId, patch)
    },
})

export const deleteTransaction = mutation({
    args: {
        transactionId: v.id('transactions'),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)

        const tx = await ctx.db.get(args.transactionId)
        if (!tx) throw new Error('Transaction not found')
        if (tx.userId !== user._id) throw new Error('Not authorized')

        await ctx.db.delete(args.transactionId)
    },
})
