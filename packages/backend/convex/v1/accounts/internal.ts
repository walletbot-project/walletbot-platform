import { v } from 'convex/values'
import { internal } from '../../_generated/api'
import type { MutationCtx } from '../../_generated/server'
import { internalMutation } from '../../_generated/server'
import { inflowsByAccount, outflowsByAccount } from '../../aggregates'
import { nextSeq, writeTombstone } from '../../sync/helpers'
import { resolveAccountId } from './helpers'

// Batch size for the transaction repoint below. Kept well under Convex's
// per-mutation read/write budget so an account with a lot of history never
// blows a single invocation — see `transactions/backfill.ts` for the same
// pagination-and-reschedule shape.
const MERGE_BATCH = 200

// Continues (and eventually finishes) an account merge kicked off by
// `reconcileAccountDuplicates`. Repoints every transaction that still
// references `loserId` — as source (`accountId`) or destination
// (`toAccountId`) — onto `winnerId`, then deletes the (already-archived)
// loser and writes its merge tombstone.
//
// Idempotent and safe to re-run: each batch only touches rows that still
// match the loser id, so re-scheduling after a partial run just continues
// from where the data is, and `finalizeMerge` no-ops once the loser is gone.
export const mergeTransactionBatch = internalMutation({
    args: {
        userId: v.string(),
        loserId: v.string(),
        winnerId: v.string(),
        sourceCursor: v.union(v.string(), v.null()),
        sourceDone: v.boolean(),
        destCursor: v.union(v.string(), v.null()),
        destDone: v.boolean(),
    },
    handler: async (ctx, args) => {
        // The winner may itself have since been merged into another account
        // (e.g. a later push collapsed a 3-way duplicate) — follow the chain
        // so we never repoint onto a now-defunct account.
        const winnerId = await resolveAccountId(ctx, args.userId, args.winnerId)
        const winner = await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', args.userId).eq('id', winnerId),
            )
            .unique()
        if (!winner) return null

        const seq = await nextSeq(ctx, args.userId)

        let sourceDone = args.sourceDone
        let sourceCursor = args.sourceCursor
        if (!sourceDone) {
            const page = await ctx.db
                .query('transactions')
                .withIndex('by_user_account_date', (q) =>
                    q.eq('userId', args.userId).eq('accountId', args.loserId),
                )
                .paginate({ numItems: MERGE_BATCH, cursor: sourceCursor })
            for (const txn of page.page) {
                // Would create a self-transfer (source === destination).
                // Leave it pointing at the loser rather than corrupt that
                // invariant — see finalizeMerge below.
                if (txn.toAccountId === winner.id) continue
                const oldDoc = txn
                await ctx.db.patch(txn._id, { accountId: winner.id, seq })
                const newDoc = await ctx.db.get(txn._id)
                if (newDoc) {
                    await outflowsByAccount.replace(ctx, oldDoc, newDoc)
                    await inflowsByAccount.replace(ctx, oldDoc, newDoc)
                }
            }
            sourceDone = page.isDone
            sourceCursor = page.continueCursor
        }

        let destDone = args.destDone
        let destCursor = args.destCursor
        if (!destDone) {
            const page = await ctx.db
                .query('transactions')
                .withIndex('by_user_to_account_date', (q) =>
                    q.eq('userId', args.userId).eq('toAccountId', args.loserId),
                )
                .paginate({ numItems: MERGE_BATCH, cursor: destCursor })
            for (const txn of page.page) {
                if (txn.accountId === winner.id) continue
                const oldDoc = txn
                await ctx.db.patch(txn._id, { toAccountId: winner.id, seq })
                const newDoc = await ctx.db.get(txn._id)
                if (newDoc) {
                    await outflowsByAccount.replace(ctx, oldDoc, newDoc)
                    await inflowsByAccount.replace(ctx, oldDoc, newDoc)
                }
            }
            destDone = page.isDone
            destCursor = page.continueCursor
        }

        if (!sourceDone || !destDone) {
            await ctx.scheduler.runAfter(
                0,
                internal.v1.accounts.internal.mergeTransactionBatch,
                {
                    userId: args.userId,
                    loserId: args.loserId,
                    winnerId: winner.id,
                    sourceCursor,
                    sourceDone,
                    destCursor,
                    destDone,
                },
            )
            return null
        }

        await finalizeMerge(ctx, args.userId, seq, args.loserId, winner.id)
        return null
    },
})

async function finalizeMerge(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    loserId: string,
    winnerId: string,
): Promise<void> {
    const loser = await ctx.db
        .query('accounts')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', loserId),
        )
        .unique()
    if (!loser) return // already finalized

    // The self-transfer guard above may have left a transaction referencing
    // the loser — it can't be safely deleted then. Leave it archived rather
    // than merged; this is the same accepted risk as pre-existing duplicates
    // from before WAL-148, which this feature doesn't retroactively touch.
    const stillReferenced =
        (await ctx.db
            .query('transactions')
            .withIndex('by_user_account_date', (q) =>
                q.eq('userId', userId).eq('accountId', loserId),
            )
            .first()) ??
        (await ctx.db
            .query('transactions')
            .withIndex('by_user_to_account_date', (q) =>
                q.eq('userId', userId).eq('toAccountId', loserId),
            )
            .first())
    if (stillReferenced) return

    await ctx.db.delete(loser._id)
    await writeTombstone(ctx, {
        userId,
        tableName: 'accounts',
        entityId: loserId,
        seq,
        mergedIntoId: winnerId,
    })
}
