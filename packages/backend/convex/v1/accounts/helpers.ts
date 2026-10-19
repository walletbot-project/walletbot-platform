import { internal } from '../../_generated/api'
import type { Doc, Id } from '../../_generated/dataModel'
import type { MutationCtx, QueryCtx } from '../../_generated/server'
import { nextSeq } from '../../sync/helpers'

// Business rule: within a user's accounts, name+currency must be unique
// (case/whitespace-insensitive), but the same name is allowed across
// different currencies. Archived accounts don't count — archiving frees up
// the name+currency combo for reuse. Enforced on the direct mutation path
// (mutations.ts), which rejects the write outright — that's fine there
// because it's a single synchronous device round-trip. The sync push path
// (v1/sync/mutations.ts) can't reject the same way (see
// reconcileAccountDuplicates below): native accounts are created locally and
// only ever reach the server through sync, so two offline devices can each
// pass this same check before either has seen the other's account.
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

// Deterministic tie-break for which of two colliding accounts survives a
// merge: earliest `createdAt` wins; ties (e.g. two devices creating
// "Efectivo" in the same millisecond) break on the client-generated `id` so
// every device — regardless of push order — computes the same winner.
function isEarlierMergeCandidate(
    a: Doc<'accounts'>,
    b: Doc<'accounts'>,
): boolean {
    if (a.createdAt !== b.createdAt) return a.createdAt < b.createdAt
    return a.id < b.id
}

// Follows account-merge tombstones to find the live account a (possibly
// merged-away) client id now resolves to. Returns `accountId` unchanged if
// it's live, or if it was deleted for a reason other than a merge (no
// `mergedIntoId` on its tombstone). Bounded to 10 hops as a defensive guard
// against a redirect cycle — merge chains are never more than a couple of
// hops deep in practice.
export async function resolveAccountId(
    ctx: QueryCtx,
    userId: string,
    accountId: string,
): Promise<string> {
    let current = accountId
    for (let hops = 0; hops < 10; hops++) {
        const live = await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', current),
            )
            .unique()
        if (live) return current

        const tomb = await ctx.db
            .query('tombstones')
            .withIndex('by_user_table_entity', (q) =>
                q
                    .eq('userId', userId)
                    .eq('tableName', 'accounts')
                    .eq('entityId', current),
            )
            .unique()
        if (!tomb?.mergedIntoId) return current
        current = tomb.mergedIntoId
    }
    return current
}

// Kicks off an automatic, deterministic merge for one colliding account:
// archives `loser` immediately (so it drops out of future duplicate checks
// and `applyTransactionUpsert` lookups keep succeeding without throwing) and
// schedules the — possibly multi-batch — transaction migration that repoints
// its history onto `winner` and eventually deletes it, writing a merge
// tombstone. See `v1/accounts/internal.ts:mergeTransactionBatch`.
//
// The archive gets its own seq, later than the push that caused it: the
// pushing device acks the push's seq as already known, so a change stamped
// with that same seq would never reach it.
async function mergeAccount(
    ctx: MutationCtx,
    userId: string,
    loser: Doc<'accounts'>,
    winner: Doc<'accounts'>,
): Promise<void> {
    await ctx.db.patch(loser._id, {
        isArchived: true,
        updatedAt: BigInt(Date.now()),
        seq: await nextSeq(ctx, userId),
    })
    await ctx.scheduler.runAfter(
        0,
        internal.v1.accounts.internal.mergeTransactionBatch,
        {
            userId,
            loserId: loser.id,
            winnerId: winner.id,
            sourceCursor: null,
            sourceDone: false,
            destCursor: null,
            destDone: false,
        },
    )
}

// Finds every *active* account sharing `currency` + normalized `name` and,
// if more than one exists, merges all but a single deterministic winner into
// it (WAL-148: "unificar cuentas automáticamente" — see the PR #200 review).
//
// Must be called only after every account upsert in the current sync-push
// batch has already been applied (see v1/sync/mutations.ts), not inline
// per-upsert. Otherwise a same-batch rename swap (X and Y trading names)
// would see a transient collision with a sibling row that hasn't been
// written to its final name yet, and merge two accounts the user never
// intended to combine.
export async function reconcileAccountDuplicates(
    ctx: MutationCtx,
    userId: string,
    currency: string,
    name: string,
): Promise<void> {
    const normalized = name.trim().toLowerCase()
    const group = (
        await ctx.db
            .query('accounts')
            .withIndex('by_user_currency', (q) =>
                q.eq('userId', userId).eq('currency', currency),
            )
            .collect()
    ).filter((a) => !a.isArchived && a.name.trim().toLowerCase() === normalized)
    if (group.length <= 1) return

    let winner = group[0]
    for (const candidate of group.slice(1)) {
        if (isEarlierMergeCandidate(candidate, winner)) winner = candidate
    }

    for (const loser of group) {
        if (loser._id === winner._id) continue
        await mergeAccount(ctx, userId, loser, winner)
    }
}
