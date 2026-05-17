import type { ActionCtx, MutationCtx, QueryCtx } from '../_generated/server'
import { authComponent } from '../auth'

type AuthCtx = QueryCtx | MutationCtx | ActionCtx

export async function requireAuth(ctx: AuthCtx): Promise<string> {
    const identity = await ctx.auth.getUserIdentity()
    if (!identity) throw new Error('Unauthenticated')

    // Native JWTs (`authNative/utils.ts`) are minted with `sub = user._id`
    // from the better-auth user table, so we can skip the DB lookup.
    const convexSiteUrl = process.env.CONVEX_SITE_URL
    if (convexSiteUrl && identity.issuer === `${convexSiteUrl}/native-auth`) {
        return identity.subject
    }

    const user = await authComponent.getAuthUser(ctx)
    if (!user) throw new Error('Unauthenticated')
    return user._id
}
