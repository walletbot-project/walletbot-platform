import { v } from 'convex/values'
import { components } from '../_generated/api'
import { internalMutation, internalQuery } from '../_generated/server'
import { isAdmin, resolveFlagsForUser } from './helpers'

// Used by config/http.ts's account-config httpAction, which runs in ActionCtx
// and has no direct `ctx.db` access.
export const resolveFlagsForUserInternal = internalQuery({
    args: { userId: v.union(v.string(), v.null()) },
    handler: async (ctx, args) => {
        return await resolveFlagsForUser(ctx, args.userId)
    },
})

function authUserId(user: unknown): string | null {
    if (typeof user !== 'object' || user === null || !('_id' in user)) {
        return null
    }
    return typeof user._id === 'string' ? user._id : null
}

/**
 * Grants admin to an existing account, per deployment, from the CLI:
 * `npx convex run featureFlags/internal:grantAdmin '{"email":"…"}'`.
 * Idempotent: `isAdmin` expects at most one row per user.
 */
export const grantAdmin = internalMutation({
    args: { email: v.string() },
    handler: async (ctx, { email }) => {
        const userId = authUserId(
            await ctx.runQuery(components.betterAuth.adapter.findOne, {
                model: 'user',
                where: [{ field: 'email', value: email }],
            }),
        )
        if (userId === null) throw new Error(`No account for ${email}`)
        if (await isAdmin(ctx, userId)) return { userId, created: false }
        await ctx.db.insert('admins', {
            userId,
            email,
            createdAt: BigInt(Date.now()),
        })
        return { userId, created: true }
    },
})
