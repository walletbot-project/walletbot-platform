import type { Id } from '../_generated/dataModel'
import type { MutationCtx, QueryCtx } from '../_generated/server'

/**
 * Get the user's default account. Returns null if none found.
 */
export async function getDefaultAccount(
    ctx: QueryCtx | MutationCtx,
    userId: string,
) {
    return await ctx.db
        .query('accounts')
        .withIndex('by_userId_and_isDefault', (q) =>
            q.eq('userId', userId).eq('isDefault', true),
        )
        .first()
}

/**
 * Verify that the given account belongs to the user. Throws if not found or not owned.
 */
export async function ensureAccountOwner(
    ctx: QueryCtx | MutationCtx,
    userId: string,
    accountId: Id<'accounts'>,
) {
    const account = await ctx.db.get(accountId)
    if (!account) throw new Error('Account not found')
    if (account.userId !== userId) throw new Error('Not authorized')
    return account
}

/**
 * Default accounts seeded for new users.
 */
export const DEFAULT_ACCOUNTS = [
    {
        name: 'Cash',
        type: 'asset' as const,
        icon: '💵',
        isDefault: true,
        sortOrder: 0,
    },
    {
        name: 'Bank',
        type: 'asset' as const,
        icon: '🏦',
        isDefault: false,
        sortOrder: 1,
    },
    {
        name: 'Credit Card',
        type: 'liability' as const,
        icon: '💳',
        isDefault: false,
        sortOrder: 2,
    },
] as const
