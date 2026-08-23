import { internal } from '../_generated/api'
import type { ActionCtx, MutationCtx, QueryCtx } from '../_generated/server'
import { authComponent } from '../auth'

type AuthCtx = QueryCtx | MutationCtx | ActionCtx

/**
 * The caller's user id, or `null` when the request carries no usable identity.
 *
 * Only for endpoints that are *deliberately* reachable both ways — currently
 * `v1/feedback`, which a native local-only account (no backend user at all)
 * must be able to reach. Anything protecting user data uses [requireAuth]
 * instead: absence of an identity there is a refusal, not a branch.
 */
export async function getOptionalUserId(ctx: AuthCtx): Promise<string | null> {
    const identity = await ctx.auth.getUserIdentity()
    if (!identity) return null

    // Native JWTs (`authNative/utils.ts`) are minted with `sub = user._id`
    // from the better-auth user table, so we can skip the DB lookup.
    const convexSiteUrl = process.env.CONVEX_SITE_URL
    let userId: string
    if (convexSiteUrl && identity.issuer === `${convexSiteUrl}/native-auth`) {
        userId = identity.subject
    } else {
        const user = await authComponent.getAuthUser(ctx)
        if (!user) return null
        userId = user._id
    }

    // Both token kinds are stateless JWTs that outlive account deletion
    // (native: 24h TTL), so a purged user's still-valid token must be
    // rejected here or an offline device could sync its data back into
    // existence. One indexed point-read on a tiny table. A purged user is
    // no longer a usable identity, so this reads as `null` — [requireAuth]
    // turns that into a refusal, and the anonymous-capable endpoints treat
    // it as anonymous rather than attributing rows to a deleted user.
    const deleted =
        'db' in ctx
            ? (await ctx.db
                  .query('deletedUsers')
                  .withIndex('by_userId', (q) => q.eq('userId', userId))
                  .first()) !== null
            : await ctx.runQuery(internal.userDeletion.internal.isUserDeleted, {
                  userId,
              })
    if (deleted) return null

    return userId
}

export async function requireAuth(ctx: AuthCtx): Promise<string> {
    const userId = await getOptionalUserId(ctx)
    if (userId === null) throw new Error('Unauthenticated')
    return userId
}
