import { internal } from '../_generated/api'
import type { ActionCtx, MutationCtx, QueryCtx } from '../_generated/server'
import { authComponent } from '../auth'

type AuthCtx = QueryCtx | MutationCtx | ActionCtx

/**
 * The caller's user id, or `null` when the request carries no usable identity.
 *
 * Every check {@link requireAuth} has ever made lives here — it is now the thin
 * throwing wrapper over this. Returning `null` instead of throwing exists for
 * the one surface that is legitimately reachable unauthenticated: `v1/feedback`,
 * which native LOCAL-only accounts can call. A token that IS present but no
 * longer resolves to a live user (a purged account's still-valid JWT) also
 * comes back as `null` — treated as no identity, never as its former owner.
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
    if (deleted) return null

    return userId
}

export async function requireAuth(ctx: AuthCtx): Promise<string> {
    const userId = await getOptionalUserId(ctx)
    if (!userId) throw new Error('Unauthenticated')
    return userId
}
