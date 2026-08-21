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
    if (convexSiteUrl && identity.issuer === `${convexSiteUrl}/native-auth`) {
        return identity.subject
    }

    const user = await authComponent.getAuthUser(ctx)
    return user?._id ?? null
}

export async function requireAuth(ctx: AuthCtx): Promise<string> {
    const userId = await getOptionalUserId(ctx)
    if (userId === null) throw new Error('Unauthenticated')
    return userId
}
