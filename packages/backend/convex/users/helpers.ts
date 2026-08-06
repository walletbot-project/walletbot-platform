import { internal } from '../_generated/api'
import type { ActionCtx, MutationCtx, QueryCtx } from '../_generated/server'
import { authComponent } from '../auth'

type AuthCtx = QueryCtx | MutationCtx | ActionCtx

export async function requireAuth(ctx: AuthCtx): Promise<string> {
    const identity = await ctx.auth.getUserIdentity()
    if (!identity) throw new Error('Unauthenticated')

    // Native JWTs (`authNative/utils.ts`) are minted with `sub = user._id`
    // from the better-auth user table, so we can skip the DB lookup.
    const convexSiteUrl = process.env.CONVEX_SITE_URL
    let userId: string
    if (convexSiteUrl && identity.issuer === `${convexSiteUrl}/native-auth`) {
        userId = identity.subject
    } else {
        const user = await authComponent.getAuthUser(ctx)
        if (!user) throw new Error('Unauthenticated')
        userId = user._id
    }

    // Both token kinds are stateless JWTs that outlive account deletion
    // (native: 24h TTL), so a purged user's still-valid token must be
    // rejected here or an offline device could sync its data back into
    // existence. One indexed point-read on a tiny table.
    const deleted =
        'db' in ctx
            ? (await ctx.db
                  .query('deletedUsers')
                  .withIndex('by_userId', (q) => q.eq('userId', userId))
                  .first()) !== null
            : await ctx.runQuery(internal.userDeletion.internal.isUserDeleted, {
                  userId,
              })
    if (deleted) throw new Error('Unauthenticated')

    return userId
}
