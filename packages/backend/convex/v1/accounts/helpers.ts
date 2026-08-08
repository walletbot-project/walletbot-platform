import type { Id } from '../../_generated/dataModel'
import type { QueryCtx } from '../../_generated/server'

// Business rule: within a user's accounts, name+currency must be unique
// (case/whitespace-insensitive), but the same name is allowed across
// different currencies. Archived accounts don't count — archiving frees up
// the name+currency combo for reuse. Enforced both on the direct mutation
// path (mutations.ts) and the sync push path (v1/sync/mutations.ts), since
// native accounts are created locally and only ever reach the server through
// sync.
export async function hasDuplicateAccount(
    ctx: QueryCtx,
    userId: string,
    currency: string,
    name: string,
    excludeDocId?: Id<'accounts'>,
): Promise<boolean> {
    const normalized = name.trim().toLowerCase()
    const sameCurrency = await ctx.db
        .query('accounts')
        .withIndex('by_user_currency', (q) =>
            q.eq('userId', userId).eq('currency', currency),
        )
        .collect()
    return sameCurrency.some(
        (a) =>
            a._id !== excludeDocId &&
            !a.isArchived &&
            a.name.trim().toLowerCase() === normalized,
    )
}
