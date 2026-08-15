import { DEFAULT_CURRENCY } from '@wallet-bot/shared'
import type { MutationCtx, QueryCtx } from '../../_generated/server'

export async function getDefaultCurrency(
    ctx: QueryCtx | MutationCtx,
    userId: string,
): Promise<string> {
    const settings = await ctx.db
        .query('userSettings')
        .withIndex('by_user', (q) => q.eq('userId', userId))
        .unique()
    return settings?.defaultCurrency ?? DEFAULT_CURRENCY
}
