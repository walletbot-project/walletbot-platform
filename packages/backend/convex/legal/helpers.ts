import { CURRENT_LEGAL_VERSION, LEGAL_POLICY } from '@wallet-bot/shared'
import type { Doc } from '../_generated/dataModel'
import type { MutationCtx, QueryCtx } from '../_generated/server'

export { CURRENT_LEGAL_VERSION, LEGAL_POLICY }

/**
 * The user's newest accepted documents version. Versions are ISO dates, so
 * the `by_user_version` index order IS version order and `.order('desc')`
 * surfaces the latest; the read stays bounded to one row per call.
 */
export async function getLatestAcceptance(
    ctx: QueryCtx,
    userId: string,
): Promise<Doc<'termsAcceptances'> | null> {
    return await ctx.db
        .query('termsAcceptances')
        .withIndex('by_user_version', (q) => q.eq('userId', userId))
        .order('desc')
        .first()
}

/**
 * Idempotently record an affirmative acceptance. The first acceptance of a
 * given documents version wins: the recorded date is when the user first
 * accepted, so replays never rewrite it.
 */
export async function recordAcceptance(
    ctx: MutationCtx,
    args: {
        userId: string
        documentVersion: string
        source: 'signup' | 'gate'
    },
): Promise<void> {
    const existing = await ctx.db
        .query('termsAcceptances')
        .withIndex('by_user_version', (q) =>
            q
                .eq('userId', args.userId)
                .eq('documentVersion', args.documentVersion),
        )
        .first()
    if (existing) return
    await ctx.db.insert('termsAcceptances', {
        userId: args.userId,
        documentVersion: args.documentVersion,
        acceptedAt: BigInt(Date.now()),
        source: args.source,
    })
}
