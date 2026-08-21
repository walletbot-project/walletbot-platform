import { CURRENT_LEGAL_VERSION } from '@wallet-bot/shared'
import type { Doc } from '../_generated/dataModel'
import type { MutationCtx, QueryCtx } from '../_generated/server'

export { CURRENT_LEGAL_VERSION }

/** The user's acceptance row for the documents version currently in force. */
export async function getCurrentAcceptance(
    ctx: QueryCtx,
    userId: string,
): Promise<Doc<'termsAcceptances'> | null> {
    return await ctx.db
        .query('termsAcceptances')
        .withIndex('by_user_version', (q) =>
            q.eq('userId', userId).eq('documentVersion', CURRENT_LEGAL_VERSION),
        )
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
