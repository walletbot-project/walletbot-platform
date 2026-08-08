import { v } from 'convex/values'
import { mutation } from '../../_generated/server'
import { nextSeq, writeTombstone } from '../../sync/helpers'
import { recordFinancialAccountCreated } from '../../telemetry/metrics'
import { requireAuth } from '../../users/helpers'
import { getDefaultCurrency } from '../users/helpers'
import { hasDuplicateAccount } from './helpers'

// Business rule: an account always has a color + icon. Convex has no
// column-level defaults, so we fill them here when a writer omits them.
// Mirror the native defaults in apps/native/lib/database.dart.
const DEFAULT_ACCOUNT_COLOR = '#3B82F6'
const DEFAULT_ACCOUNT_ICON = 'wallet'

export const create = mutation({
    args: {
        id: v.string(),
        name: v.string(),
        currency: v.optional(v.string()),
        description: v.optional(v.string()),
        color: v.optional(v.string()),
        icon: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)

        const existing = await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (existing) {
            throw new Error('Account with that id already exists')
        }

        if (await hasDuplicateAccount(ctx, userId, args.currency, args.name)) {
            throw new Error(
                'An account with that name and currency already exists',
            )
        }

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())
        const currency =
            args.currency ?? (await getDefaultCurrency(ctx, userId))

        await ctx.db.insert('accounts', {
            userId,
            id: args.id,
            name: args.name,
            currency,
            description: args.description,
            color: args.color ?? DEFAULT_ACCOUNT_COLOR,
            icon: args.icon ?? DEFAULT_ACCOUNT_ICON,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq,
        })

        await recordFinancialAccountCreated(ctx, {
            userId,
            createdBy: 'form',
            ingestPath: 'direct_mutation',
        })

        return args.id
    },
})

export const update = mutation({
    args: {
        id: v.string(),
        name: v.optional(v.string()),
        currency: v.optional(v.string()),
        description: v.optional(v.string()),
        color: v.optional(v.string()),
        icon: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (!row) throw new Error('Account not found')

        if (args.name !== undefined || args.currency !== undefined) {
            const nextName = args.name ?? row.name
            const nextCurrency = args.currency ?? row.currency
            if (
                await hasDuplicateAccount(
                    ctx,
                    userId,
                    nextCurrency,
                    nextName,
                    row._id,
                )
            ) {
                throw new Error(
                    'An account with that name and currency already exists',
                )
            }
        }

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        const patch: {
            name?: string
            currency?: string
            description?: string
            color?: string
            icon?: string
        } = {}
        if (args.name !== undefined) patch.name = args.name
        if (args.currency !== undefined) patch.currency = args.currency
        if (args.description !== undefined) patch.description = args.description
        if (args.color !== undefined) patch.color = args.color
        if (args.icon !== undefined) patch.icon = args.icon

        await ctx.db.patch(row._id, {
            ...patch,
            updatedAt: now,
            seq,
        })
    },
})

export const archive = mutation({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (!row) return

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        await ctx.db.patch(row._id, {
            isArchived: true,
            updatedAt: now,
            seq,
        })

        await writeTombstone(ctx, {
            userId,
            tableName: 'accounts',
            entityId: args.id,
            seq,
        })
    },
})
