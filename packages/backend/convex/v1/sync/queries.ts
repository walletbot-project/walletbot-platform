import { v } from 'convex/values'
import type { Doc } from '../../_generated/dataModel'
import type { QueryCtx } from '../../_generated/server'
import { query } from '../../_generated/server'
import { CLIENT_OUTDATED, isClientSupported } from '../../config/helpers'
import { syncedTable } from '../../schema/sync'
import { requireAuth } from '../../users/helpers'

// Default page size if the caller doesn't override. Calibrated below the
// Convex query item-read limit (~1024 rows per index) so a single pull page
// never blows the runtime budget.
const DEFAULT_LIMIT = 200
const MAX_LIMIT = 500

const SYNCED_TABLES = [
    'accounts',
    'categories',
    'transactions',
    'tags',
    'transactionTags',
    'savedFilters',
    'dashboardWidgets',
] as const
type SyncedTable = (typeof SYNCED_TABLES)[number]

// ─────────────────────────────────────────────────────────────────────────────
// getCounter — singleton subscription target.
//
// The client subscribes to this. Every push (theirs or another device's) bumps
// `syncCounters.value` and the subscription fires, triggering a pull on the
// client. Returning the value as `bigint` is fine here because subscriptions
// don't need the diff to look "small"; any change re-fires the listener.
// ─────────────────────────────────────────────────────────────────────────────
export const getCounter = query({
    args: {},
    handler: async (ctx): Promise<bigint> => {
        const userId = await requireAuth(ctx)
        const row = await ctx.db
            .query('syncCounters')
            .withIndex('by_user', (q) => q.eq('userId', userId))
            .unique()
        return row?.value ?? 0n
    },
})

// ─────────────────────────────────────────────────────────────────────────────
// pull — paginated download of rows and tombstones with seq > since.
//
// Cursor model: a single `since: int64`. The client passes the highest seq
// it has applied. We never split a single `seq` value across two pages — if
// the boundary would land inside a `seq`, we either include every item at
// that seq or stop before it. This guarantees the next pull with
// `since = lastReturnedSeq` does not skip any rows.
//
// Item budget per source: we take `limit + 1` per table and per the
// tombstones table. Total items considered per page = (5 entity tables + 1
// tombstones) * (limit + 1). Within Convex's query-read budget for
// reasonable `limit`s (≤500).
//
// Note: the bound `limit` is on total items returned, not per table.
// ─────────────────────────────────────────────────────────────────────────────
type PullRowItem = {
    kind: 'row'
    seq: bigint
    sortKey: string
    tableName: SyncedTable
    row: Record<string, unknown>
}

type PullTombstoneItem = {
    kind: 'tombstone'
    seq: bigint
    sortKey: string
    tableName: SyncedTable
    entityId: string
    deletedAt: bigint
}

type PullItem = PullRowItem | PullTombstoneItem

function stripSystemFields<T extends { _id: unknown; _creationTime: unknown }>(
    doc: T,
): Omit<T, '_id' | '_creationTime' | 'userId'> {
    const { _id, _creationTime, ...rest } = doc as T & {
        userId?: string
    }
    void _id
    void _creationTime
    if ('userId' in rest) delete (rest as { userId?: string }).userId
    return rest as Omit<T, '_id' | '_creationTime' | 'userId'>
}

function tablePriority(t: SyncedTable): number {
    // Catalog tables before transactional tables so a client that applies in
    // sort order resolves FKs as it goes. transactionTags last because they
    // reference both transactions and tags.
    switch (t) {
        case 'accounts':
            return 0
        case 'categories':
            return 1
        case 'tags':
            return 2
        case 'transactions':
            return 3
        case 'transactionTags':
            return 4
        // Dashboard layout: saved filters before widgets (a widget's filterId
        // soft-references a saved filter).
        case 'savedFilters':
            return 5
        case 'dashboardWidgets':
            return 6
    }
}

function makeSortKey(
    seq: bigint,
    table: SyncedTable,
    id: string,
    kind: 'row' | 'tombstone',
): string {
    // Zero-padded numeric prefix so lexicographic sort matches numeric. Width
    // 20 fits any int64. Within the same seq, rows come before tombstones (so
    // a row + tombstone in the same mutation applies "row first, delete after"
    // which is closer to user intent), and within rows we order by table
    // priority so FKs resolve cleanly.
    const seqStr = seq.toString().padStart(20, '0')
    const kindFlag = kind === 'row' ? '0' : '1'
    const tablePri = tablePriority(table).toString()
    return `${seqStr}:${kindFlag}:${tablePri}:${table}:${id}`
}

async function fetchTableRows(
    ctx: QueryCtx,
    userId: string,
    table: SyncedTable,
    since: bigint,
    take: number,
): Promise<PullRowItem[]> {
    let docs: Array<Doc<SyncedTable>>
    switch (table) {
        case 'accounts':
            docs = await ctx.db
                .query('accounts')
                .withIndex('by_user_seq', (q) =>
                    q.eq('userId', userId).gt('seq', since),
                )
                .order('asc')
                .take(take)
            break
        case 'categories':
            docs = await ctx.db
                .query('categories')
                .withIndex('by_user_seq', (q) =>
                    q.eq('userId', userId).gt('seq', since),
                )
                .order('asc')
                .take(take)
            break
        case 'transactions':
            docs = await ctx.db
                .query('transactions')
                .withIndex('by_user_seq', (q) =>
                    q.eq('userId', userId).gt('seq', since),
                )
                .order('asc')
                .take(take)
            break
        case 'tags':
            docs = await ctx.db
                .query('tags')
                .withIndex('by_user_seq', (q) =>
                    q.eq('userId', userId).gt('seq', since),
                )
                .order('asc')
                .take(take)
            break
        case 'transactionTags':
            docs = await ctx.db
                .query('transactionTags')
                .withIndex('by_user_seq', (q) =>
                    q.eq('userId', userId).gt('seq', since),
                )
                .order('asc')
                .take(take)
            break
        case 'savedFilters':
            docs = await ctx.db
                .query('savedFilters')
                .withIndex('by_user_seq', (q) =>
                    q.eq('userId', userId).gt('seq', since),
                )
                .order('asc')
                .take(take)
            break
        case 'dashboardWidgets':
            docs = await ctx.db
                .query('dashboardWidgets')
                .withIndex('by_user_seq', (q) =>
                    q.eq('userId', userId).gt('seq', since),
                )
                .order('asc')
                .take(take)
            break
    }
    return docs.map((d) => ({
        kind: 'row' as const,
        seq: d.seq,
        sortKey: makeSortKey(d.seq, table, d.id, 'row'),
        tableName: table,
        row: stripSystemFields(d),
    }))
}

export const pull = query({
    args: {
        since: v.int64(),
        limit: v.optional(v.number()),
        platform: v.string(),
        appVersion: v.string(),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        // Reject clients below the platform floor before returning any data —
        // "old clients fail closed on sync" (CLAUDE.md). Fails open for a client
        // that can't report its version (unknown → supported, see config helpers).
        if (!isClientSupported(args.platform, args.appVersion)) {
            return { ok: false as const, error: CLIENT_OUTDATED }
        }
        const limit = Math.min(
            Math.max(1, Math.floor(args.limit ?? DEFAULT_LIMIT)),
            MAX_LIMIT,
        )

        const buffer: PullItem[] = []

        for (const table of SYNCED_TABLES) {
            const items = await fetchTableRows(
                ctx,
                userId,
                table,
                args.since,
                limit + 1,
            )
            for (const item of items) buffer.push(item)
        }

        const tombDocs = await ctx.db
            .query('tombstones')
            .withIndex('by_user_seq', (q) =>
                q.eq('userId', userId).gt('seq', args.since),
            )
            .order('asc')
            .take(limit + 1)
        for (const t of tombDocs) {
            buffer.push({
                kind: 'tombstone' as const,
                seq: t.seq,
                sortKey: makeSortKey(
                    t.seq,
                    t.tableName,
                    t.entityId,
                    'tombstone',
                ),
                tableName: t.tableName,
                entityId: t.entityId,
                deletedAt: t.deletedAt,
            })
        }

        buffer.sort((a, b) =>
            a.sortKey < b.sortKey ? -1 : a.sortKey > b.sortKey ? 1 : 0,
        )

        const counterRow = await ctx.db
            .query('syncCounters')
            .withIndex('by_user', (q) => q.eq('userId', userId))
            .unique()
        const currentCounter = counterRow?.value ?? 0n

        if (buffer.length === 0) {
            return {
                rows: [] as Array<{
                    tableName: SyncedTable
                    row: Record<string, unknown>
                }>,
                tombstones: [] as Array<{
                    tableName: SyncedTable
                    entityId: string
                    deletedAt: bigint
                    seq: bigint
                }>,
                nextCursor: null as bigint | null,
                hasMore: false,
                currentCounter,
            }
        }

        // Choose a cutoff that never splits a single `seq`. If we have more
        // items than `limit`, walk back from `limit` to a clean seq boundary.
        // Edge case: if every item up to index `limit` shares the boundary
        // seq, we must take the full run of that seq even if it exceeds
        // `limit` — otherwise we can't make progress.
        let cutoff: number
        if (buffer.length <= limit) {
            cutoff = buffer.length
        } else {
            const boundarySeq = buffer[limit].seq
            let i = limit
            while (i > 0 && buffer[i - 1].seq === boundarySeq) i--
            if (i === 0) {
                let j = limit
                while (j < buffer.length && buffer[j].seq === boundarySeq) j++
                cutoff = j
            } else {
                cutoff = i
            }
        }

        const taken = buffer.slice(0, cutoff)
        const rows = taken
            .filter((i): i is PullRowItem => i.kind === 'row')
            .map((i) => ({ tableName: i.tableName, row: i.row }))
        const tombstones = taken
            .filter((i): i is PullTombstoneItem => i.kind === 'tombstone')
            .map((i) => ({
                tableName: i.tableName,
                entityId: i.entityId,
                deletedAt: i.deletedAt,
                seq: i.seq,
            }))

        const hasMore = buffer.length > cutoff
        const lastSeq = taken[taken.length - 1].seq
        const nextCursor = hasMore ? lastSeq : null

        return {
            rows,
            tombstones,
            nextCursor,
            hasMore,
            currentCounter,
        }
    },
})

// Re-exported so the push mutation file can reuse the literal-union validator.
export { syncedTable }
