import { v } from 'convex/values'
import { mutation } from '../_generated/server'
import { requireAuth } from '../lib/auth'
import { accountTypeValidator, currencyValidator } from '../lib/validators'
import {
    DEFAULT_ACCOUNTS,
    ensureAccountOwner,
    getDefaultAccount,
} from './helpers'

export const createAccount = mutation({
    args: {
        name: v.string(),
        type: accountTypeValidator,
        icon: v.string(),
        currency: currencyValidator,
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)

        // Next sort order
        const existing = await ctx.db
            .query('accounts')
            .withIndex('by_userId', (q) => q.eq('userId', user._id))
            .take(50)
        const maxSort = existing.reduce(
            (max, a) => Math.max(max, a.sortOrder),
            -1,
        )

        // First account becomes default
        const isDefault = existing.length === 0

        return await ctx.db.insert('accounts', {
            userId: user._id,
            name: args.name.trim(),
            type: args.type,
            icon: args.icon,
            isDefault,
            sortOrder: maxSort + 1,
            currency: args.currency,
        })
    },
})

export const updateAccount = mutation({
    args: {
        accountId: v.id('accounts'),
        name: v.optional(v.string()),
        type: v.optional(accountTypeValidator),
        icon: v.optional(v.string()),
        currency: v.optional(currencyValidator),
        sortOrder: v.optional(v.number()),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)
        await ensureAccountOwner(ctx, user._id, args.accountId)

        const { accountId, ...updates } = args
        const patch: Record<string, string | number> = {}
        if (updates.name !== undefined) patch.name = updates.name.trim()
        if (updates.type !== undefined) patch.type = updates.type
        if (updates.icon !== undefined) patch.icon = updates.icon
        if (updates.currency !== undefined) patch.currency = updates.currency
        if (updates.sortOrder !== undefined) patch.sortOrder = updates.sortOrder

        await ctx.db.patch(accountId, patch)
    },
})

export const deleteAccount = mutation({
    args: {
        accountId: v.id('accounts'),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)
        await ensureAccountOwner(ctx, user._id, args.accountId)

        // Check for transactions referencing this account
        const fromTx = await ctx.db
            .query('transactions')
            .withIndex('by_userId_and_fromAccountId', (q) =>
                q.eq('userId', user._id).eq('fromAccountId', args.accountId),
            )
            .first()
        if (fromTx)
            throw new Error('Cannot delete an account that has transactions')

        const toTx = await ctx.db
            .query('transactions')
            .withIndex('by_userId_and_toAccountId', (q) =>
                q.eq('userId', user._id).eq('toAccountId', args.accountId),
            )
            .first()
        if (toTx)
            throw new Error('Cannot delete an account that has transactions')

        await ctx.db.delete(args.accountId)
    },
})

export const setDefaultAccount = mutation({
    args: {
        accountId: v.id('accounts'),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)
        await ensureAccountOwner(ctx, user._id, args.accountId)

        // Unset current default
        const currentDefault = await getDefaultAccount(ctx, user._id)
        if (currentDefault) {
            await ctx.db.patch(currentDefault._id, { isDefault: false })
        }

        // Set new default
        await ctx.db.patch(args.accountId, { isDefault: true })
    },
})

export const seedDefaultAccounts = mutation({
    args: {},
    handler: async (ctx) => {
        const user = await requireAuth(ctx)

        // Check if already seeded
        const existing = await ctx.db
            .query('accounts')
            .withIndex('by_userId', (q) => q.eq('userId', user._id))
            .first()
        if (existing) return

        for (const account of DEFAULT_ACCOUNTS) {
            await ctx.db.insert('accounts', {
                userId: user._id,
                name: account.name,
                type: account.type,
                icon: account.icon,
                isDefault: account.isDefault,
                sortOrder: account.sortOrder,
                currency: 'USD',
            })
        }
    },
})
