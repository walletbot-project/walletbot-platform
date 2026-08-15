import { v } from 'convex/values'
import { mutation } from '../../_generated/server'
import { requireAdmin } from '../../featureFlags/helpers'
import { isKnownFlagKey, KNOWN_FLAGS } from '../../featureFlags/utils'
import { requireAuth } from '../../users/helpers'

export const setFlagDefault = mutation({
    args: { key: v.string(), enabled: v.boolean() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await requireAdmin(ctx, userId)
        if (!isKnownFlagKey(args.key)) throw new Error('Unknown flag key')

        const existing = await ctx.db
            .query('featureFlags')
            .withIndex('by_key', (q) => q.eq('key', args.key))
            .unique()
        const now = BigInt(Date.now())

        if (existing) {
            await ctx.db.patch(existing._id, {
                enabledByDefault: args.enabled,
                updatedAt: now,
                updatedBy: userId,
            })
            return
        }

        const flag = KNOWN_FLAGS.find((f) => f.key === args.key)
        await ctx.db.insert('featureFlags', {
            key: args.key,
            description: flag?.description ?? '',
            enabledByDefault: args.enabled,
            updatedAt: now,
            updatedBy: userId,
        })
    },
})

export const setUserOverride = mutation({
    args: {
        flagKey: v.string(),
        targetUserId: v.string(),
        enabled: v.boolean(),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await requireAdmin(ctx, userId)
        if (!isKnownFlagKey(args.flagKey)) throw new Error('Unknown flag key')

        const existing = await ctx.db
            .query('featureFlagOverrides')
            .withIndex('by_flag_user', (q) =>
                q.eq('flagKey', args.flagKey).eq('userId', args.targetUserId),
            )
            .unique()
        const now = BigInt(Date.now())

        if (existing) {
            await ctx.db.patch(existing._id, {
                enabled: args.enabled,
                updatedAt: now,
                updatedBy: userId,
            })
            return
        }

        await ctx.db.insert('featureFlagOverrides', {
            flagKey: args.flagKey,
            userId: args.targetUserId,
            enabled: args.enabled,
            updatedAt: now,
            updatedBy: userId,
        })
    },
})

export const removeUserOverride = mutation({
    args: { flagKey: v.string(), targetUserId: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await requireAdmin(ctx, userId)

        const existing = await ctx.db
            .query('featureFlagOverrides')
            .withIndex('by_flag_user', (q) =>
                q.eq('flagKey', args.flagKey).eq('userId', args.targetUserId),
            )
            .unique()
        if (existing) await ctx.db.delete(existing._id)
    },
})
