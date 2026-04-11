import type { MutationCtx, QueryCtx } from '../_generated/server'
import { authComponent } from '../auth'

/**
 * Require an authenticated user. Throws if not logged in.
 * Returns the user object with `_id` usable as userId.
 */
export async function requireAuth(ctx: QueryCtx | MutationCtx) {
    const user = await authComponent.getAuthUser(ctx)
    if (!user) {
        throw new Error('Not authenticated')
    }
    return user
}
