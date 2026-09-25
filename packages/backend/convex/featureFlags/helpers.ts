import type { MutationCtx, QueryCtx } from '../_generated/server'
import { type FlagKey, KNOWN_FLAGS } from './utils'

/**
 * A flag's value with no user applied, for callers that have no identity to
 * override against (an unauthenticated native local account). Same precedence
 * as [resolveFlagsForUser] minus the override step.
 */
export async function isFlagEnabledGlobally(
    ctx: QueryCtx | MutationCtx,
    key: FlagKey,
): Promise<boolean> {
    const row = await ctx.db
        .query('featureFlags')
        .withIndex('by_key', (q) => q.eq('key', key))
        .unique()
    if (row) return row.enabledByDefault
    return (
        KNOWN_FLAGS.find((flag) => flag.key === key)?.enabledByDefault ?? false
    )
}

/** One flag for one user, with the same precedence as [resolveFlagsForUser]. */
export async function isFlagEnabledForUser(
    ctx: QueryCtx | MutationCtx,
    key: FlagKey,
    userId: string,
): Promise<boolean> {
    const override = await ctx.db
        .query('featureFlagOverrides')
        .withIndex('by_flag_user', (q) =>
            q.eq('flagKey', key).eq('userId', userId),
        )
        .unique()
    if (override) return override.enabled
    return isFlagEnabledGlobally(ctx, key)
}

export async function requireAdmin(
    ctx: QueryCtx | MutationCtx,
    userId: string,
): Promise<void> {
    const admin = await ctx.db
        .query('admins')
        .withIndex('by_user_id', (q) => q.eq('userId', userId))
        .unique()
    if (!admin) throw new Error('Forbidden')
}

export async function isAdmin(
    ctx: QueryCtx | MutationCtx,
    userId: string,
): Promise<boolean> {
    const admin = await ctx.db
        .query('admins')
        .withIndex('by_user_id', (q) => q.eq('userId', userId))
        .unique()
    return admin !== null
}

export async function resolveFlagsForUser(
    ctx: QueryCtx,
    userId: string | null,
): Promise<Record<FlagKey, boolean>> {
    const result = {} as Record<FlagKey, boolean>
    for (const flag of KNOWN_FLAGS) {
        const row = await ctx.db
            .query('featureFlags')
            .withIndex('by_key', (q) => q.eq('key', flag.key))
            .unique()
        let enabled = row?.enabledByDefault ?? flag.enabledByDefault
        if (userId) {
            const override = await ctx.db
                .query('featureFlagOverrides')
                .withIndex('by_flag_user', (q) =>
                    q.eq('flagKey', flag.key).eq('userId', userId),
                )
                .unique()
            if (override) enabled = override.enabled
        }
        result[flag.key] = enabled
    }
    return result
}
