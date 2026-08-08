import { v } from 'convex/values'
import { query } from '../../_generated/server'
import { authComponent } from '../../auth'
import {
    isAdmin,
    requireAdmin,
    resolveFlagsForUser,
} from '../../featureFlags/helpers'
import { KNOWN_FLAGS } from '../../featureFlags/utils'
import { requireAuth } from '../../users/helpers'

export const getMyFlags = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        return await resolveFlagsForUser(ctx, userId)
    },
})

export const getMyAdminStatus = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        return await isAdmin(ctx, userId)
    },
})

export const listFlags = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        await requireAdmin(ctx, userId)
        return await Promise.all(
            KNOWN_FLAGS.map(async (flag) => {
                const row = await ctx.db
                    .query('featureFlags')
                    .withIndex('by_key', (q) => q.eq('key', flag.key))
                    .unique()
                return {
                    key: flag.key,
                    description: flag.description,
                    enabledByDefault:
                        row?.enabledByDefault ?? flag.enabledByDefault,
                }
            }),
        )
    },
})

export const listOverrides = query({
    args: { flagKey: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await requireAdmin(ctx, userId)
        const overrides = await ctx.db
            .query('featureFlagOverrides')
            .withIndex('by_flag_user', (q) => q.eq('flagKey', args.flagKey))
            .take(500)
        return await Promise.all(
            overrides.map(async (override) => {
                const user = await authComponent.getAnyUserById(
                    ctx,
                    override.userId,
                )
                return {
                    userId: override.userId,
                    email: user?.email ?? override.userId,
                    enabled: override.enabled,
                }
            }),
        )
    },
})
