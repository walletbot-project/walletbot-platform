import type { MutationCtx, QueryCtx } from '../_generated/server'
import { requireAdmin } from '../featureFlags/helpers'
import { requireAuth } from '../users/helpers'

/**
 * The gate every back-office read goes through: an authenticated caller who is
 * in `admins`. The client's own idea of whether it is an admin (the
 * `getMyAdminStatus` query that decides what the UI shows) is never consulted
 * here — every function re-checks on the server.
 */
export async function requireAdminCaller(
    ctx: QueryCtx | MutationCtx,
): Promise<string> {
    const userId = await requireAuth(ctx)
    await requireAdmin(ctx, userId)
    return userId
}
