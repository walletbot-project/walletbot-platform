import { pastCutoffBigInt } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internal } from '../../_generated/api'
import type { Doc } from '../../_generated/dataModel'
import type { MutationCtx } from '../../_generated/server'
import { mutation } from '../../_generated/server'
import { inflowsByAccount, outflowsByAccount } from '../../aggregates'
import { CLIENT_OUTDATED, isClientSupported } from '../../config/helpers'
import { syncedTable } from '../../schema/sync'
import { supportsRecurrences } from '../../sync/compatibility'
import { aggregateInsert, aggregateReplace } from '../../transactions/helpers'
import { requireAuth } from '../../users/helpers'
import {
    reconcileAccountDuplicates,
    resolveAccountId,
} from '../accounts/helpers'

const accountUpsert = v.object({
    id: v.string(),
    name: v.string(),
    currency: v.string(),
    description: v.optional(v.string()),
    color: v.string(),
    icon: v.string(),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const categoryUpsert = v.object({
    id: v.string(),
    name: v.string(),
    description: v.optional(v.string()),
    color: v.string(),
    icon: v.string(),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const tagUpsert = v.object({
    id: v.string(),
    name: v.string(),
    description: v.optional(v.string()),
    parentId: v.optional(v.string()),
    color: v.string(),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const transactionUpsert = v.object({
    id: v.string(),
    type: v.union(
        v.literal('expense'),
        v.literal('income'),
        v.literal('transfer'),
        v.literal('balance_adjustment'),
    ),
    name: v.string(),
    description: v.optional(v.string()),
    status: v.union(v.literal('pending'), v.literal('cleared')),
    date: v.int64(),
    // Optional for backward-compat: older clients don't send it. Defaults to
    // true on insert (matches the column default).
    dateConfirmed: v.optional(v.boolean()),
    timeStatus: v.optional(
        v.union(
            v.literal('confirmed'),
            v.literal('approximation'),
            v.literal('none'),
        ),
    ),
    accountId: v.string(),
    categoryId: v.string(),
    amount: v.int64(),
    currency: v.string(),
    toAccountId: v.optional(v.string()),
    toAmount: v.optional(v.int64()),
    toCurrency: v.optional(v.string()),
    exchangeRate: v.optional(v.number()),
    balanceAfter: v.optional(v.int64()),
    // Set on an occurrence of a recurring rule; absent on a one-off. Optional
    // for backward-compat, like `dateConfirmed` above: a client from before
    // v5 simply never sends them; replacement preserves the stored link.
    recurrenceId: v.optional(v.string()),
    recurrenceIndex: v.optional(v.int64()),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const recurrenceUpsert = v.object({
    id: v.string(),
    frequency: v.union(
        v.literal('daily'),
        v.literal('weekly'),
        v.literal('monthly'),
        v.literal('yearly'),
        v.literal('customDays'),
    ),
    dayInterval: v.optional(v.int64()),
    anchorDate: v.int64(),
    endDate: v.optional(v.int64()),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const transactionTagUpsert = v.object({
    id: v.string(),
    transactionId: v.string(),
    tagId: v.string(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const savedFilterUpsert = v.object({
    id: v.string(),
    name: v.string(),
    config: v.string(),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const dashboardWidgetUpsert = v.object({
    id: v.string(),
    type: v.string(),
    filterId: v.optional(v.string()),
    position: v.number(),
    width: v.string(),
    options: v.string(),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const agentMemoryUpsert = v.object({
    id: v.string(),
    content: v.string(),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const tombstoneArg = v.object({
    tableName: syncedTable,
    entityId: v.string(),
    deletedAt: v.int64(),
})

// ─────────────────────────────────────────────────────────────────────────────
// Push handler.
//
// Each invocation is one chunk = one mutation = one bump of the user's
// counter. Failure modes:
//  - `cursor_mismatch` → client must drain pull and retry.
//  - validation error → throws, no state changes (Convex rolls back).
// ─────────────────────────────────────────────────────────────────────────────

type AccountUpsert = {
    id: string
    name: string
    currency: string
    description?: string
    color: string
    icon: string
    isArchived: boolean
    createdAt: bigint
    updatedAt: bigint
}
type CategoryUpsert = {
    id: string
    name: string
    description?: string
    color: string
    icon: string
    isArchived: boolean
    createdAt: bigint
    updatedAt: bigint
}
type TagUpsert = {
    id: string
    name: string
    description?: string
    parentId?: string
    color: string
    isArchived: boolean
    createdAt: bigint
    updatedAt: bigint
}
type TransactionUpsert = {
    id: string
    type: 'expense' | 'income' | 'transfer' | 'balance_adjustment'
    name: string
    description?: string
    status: 'pending' | 'cleared'
    date: bigint
    dateConfirmed?: boolean
    timeStatus?: 'confirmed' | 'approximation' | 'none'
    accountId: string
    categoryId: string
    amount: bigint
    currency: string
    toAccountId?: string
    toAmount?: bigint
    toCurrency?: string
    exchangeRate?: number
    balanceAfter?: bigint
    recurrenceId?: string
    recurrenceIndex?: bigint
    isArchived: boolean
    createdAt: bigint
    updatedAt: bigint
}
type TransactionTagUpsert = {
    id: string
    transactionId: string
    tagId: string
    createdAt: bigint
    updatedAt: bigint
}
type SavedFilterUpsert = {
    id: string
    name: string
    config: string
    isArchived: boolean
    createdAt: bigint
    updatedAt: bigint
}
type DashboardWidgetUpsert = {
    id: string
    type: string
    filterId?: string
    position: number
    width: string
    options: string
    isArchived: boolean
    createdAt: bigint
    updatedAt: bigint
}
type AgentMemoryUpsert = {
    id: string
    content: string
    isArchived: boolean
    createdAt: bigint
    updatedAt: bigint
}

type RecurrenceUpsert = {
    id: string
    frequency: 'daily' | 'weekly' | 'monthly' | 'yearly' | 'customDays'
    dayInterval?: bigint
    anchorDate: bigint
    endDate?: bigint
    isArchived: boolean
    createdAt: bigint
    updatedAt: bigint
}

type SyncedTableName =
    | 'accounts'
    | 'categories'
    | 'transactions'
    | 'tags'
    | 'transactionTags'
    | 'recurrences'
    | 'savedFilters'
    | 'dashboardWidgets'
    | 'agentMemories'

async function clearTombstone(
    ctx: MutationCtx,
    userId: string,
    tableName: SyncedTableName,
    entityId: string,
): Promise<void> {
    const existing = await ctx.db
        .query('tombstones')
        .withIndex('by_user_table_entity', (q) =>
            q
                .eq('userId', userId)
                .eq('tableName', tableName)
                .eq('entityId', entityId),
        )
        .unique()
    if (existing) await ctx.db.delete(existing._id)
}

// Key used to reconcile name+currency duplicates after a batch of account
// upserts has been fully applied. Returned only for active accounts —
// archived ones don't participate in the uniqueness rule.
type AccountReconcileKey = { currency: string; name: string }

async function applyAccountUpsert(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    payload: AccountUpsert,
): Promise<AccountReconcileKey | null> {
    const existing = await ctx.db
        .query('accounts')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.id),
        )
        .unique()
    const doc: Omit<Doc<'accounts'>, '_id' | '_creationTime'> = {
        userId,
        id: payload.id,
        name: payload.name,
        currency: payload.currency,
        description: payload.description,
        color: payload.color,
        icon: payload.icon,
        isArchived: payload.isArchived,
        createdAt: payload.createdAt,
        updatedAt: payload.updatedAt,
        seq,
    }
    if (existing) {
        if (existing.currency !== payload.currency) {
            throw new Error(
                `account ${payload.id}: currency cannot change once set`,
            )
        }
        await ctx.db.replace(existing._id, doc)
    } else {
        await ctx.db.insert('accounts', doc)
    }
    await clearTombstone(ctx, userId, 'accounts', payload.id)

    // Name+currency uniqueness (WAL-148) is enforced by merging duplicates
    // rather than rejecting the write — see reconcileAccountDuplicates,
    // called once per unique (currency, name) after every upsert in this
    // push has been applied.
    if (payload.isArchived) return null
    return { currency: payload.currency, name: payload.name }
}

async function applyCategoryUpsert(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    payload: CategoryUpsert,
): Promise<void> {
    const existing = await ctx.db
        .query('categories')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.id),
        )
        .unique()
    const doc: Omit<Doc<'categories'>, '_id' | '_creationTime'> = {
        userId,
        id: payload.id,
        name: payload.name,
        description: payload.description,
        color: payload.color,
        icon: payload.icon,
        isArchived: payload.isArchived,
        createdAt: payload.createdAt,
        updatedAt: payload.updatedAt,
        seq,
    }
    if (existing) {
        await ctx.db.replace(existing._id, doc)
    } else {
        await ctx.db.insert('categories', doc)
    }
    await clearTombstone(ctx, userId, 'categories', payload.id)
}

async function applyTagUpsert(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    payload: TagUpsert,
): Promise<void> {
    if (payload.parentId === payload.id) {
        throw new Error(`tag ${payload.id}: cannot be its own parent`)
    }
    if (payload.parentId) {
        // Parent must exist and belong to the user. We don't fail if the
        // parent is also in this chunk's upserts — Convex sees inserts
        // immediately within the same transaction.
        const parent = await ctx.db
            .query('tags')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', payload.parentId as string),
            )
            .unique()
        if (!parent) {
            throw new Error(
                `tag ${payload.id}: parent ${payload.parentId} not found`,
            )
        }
    }

    const existing = await ctx.db
        .query('tags')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.id),
        )
        .unique()
    const doc: Omit<Doc<'tags'>, '_id' | '_creationTime'> = {
        userId,
        id: payload.id,
        name: payload.name,
        description: payload.description,
        parentId: payload.parentId,
        color: payload.color,
        isArchived: payload.isArchived,
        createdAt: payload.createdAt,
        updatedAt: payload.updatedAt,
        seq,
    }
    if (existing) {
        await ctx.db.replace(existing._id, doc)
    } else {
        await ctx.db.insert('tags', doc)
    }
    await clearTombstone(ctx, userId, 'tags', payload.id)
}

async function applyTransactionUpsert(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    payload: TransactionUpsert,
): Promise<void> {
    // A merged-away account id (WAL-148 auto-merge) still needs to resolve
    // to its live replacement: a dirty local row created before the device
    // learned about the merge, or a device that hasn't pulled the merge
    // tombstone yet, can otherwise push a reference to an id that no longer
    // exists.
    const accountId = await resolveAccountId(ctx, userId, payload.accountId)
    const account = await ctx.db
        .query('accounts')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', accountId),
        )
        .unique()
    if (!account) {
        throw new Error(
            `transaction ${payload.id}: accountId ${payload.accountId} not found`,
        )
    }
    if (account.currency !== payload.currency) {
        throw new Error(
            `transaction ${payload.id}: currency ${payload.currency} does not match account ${payload.accountId} currency ${account.currency}`,
        )
    }

    if (payload.categoryId) {
        const cat = await ctx.db
            .query('categories')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', payload.categoryId),
            )
            .unique()
        if (!cat) {
            throw new Error(
                `transaction ${payload.id}: categoryId ${payload.categoryId} not found`,
            )
        }
    }

    let toAccountId: string | undefined
    if (payload.type === 'transfer') {
        if (!payload.toAccountId) {
            throw new Error(
                `transaction ${payload.id}: transfer requires toAccountId`,
            )
        }
        toAccountId = await resolveAccountId(ctx, userId, payload.toAccountId)
        if (toAccountId === accountId) {
            throw new Error(
                `transaction ${payload.id}: source and destination accounts must differ`,
            )
        }
        const toAcc = await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', toAccountId as string),
            )
            .unique()
        if (!toAcc) {
            throw new Error(
                `transaction ${payload.id}: toAccountId ${payload.toAccountId} not found`,
            )
        }
        if (payload.toCurrency && payload.toCurrency !== toAcc.currency) {
            throw new Error(
                `transaction ${payload.id}: toCurrency ${payload.toCurrency} does not match account ${payload.toAccountId} currency ${toAcc.currency}`,
            )
        }
        if (payload.toAmount === undefined) {
            throw new Error(
                `transaction ${payload.id}: transfer requires toAmount`,
            )
        }
    }

    if (payload.type === 'balance_adjustment') {
        if (payload.balanceAfter === undefined) {
            throw new Error(
                `transaction ${payload.id}: balance_adjustment requires balanceAfter`,
            )
        }
    }

    const existing = await ctx.db
        .query('transactions')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.id),
        )
        .unique()

    const doc: Omit<Doc<'transactions'>, '_id' | '_creationTime'> = {
        userId,
        id: payload.id,
        type: payload.type,
        name: payload.name,
        description: payload.description,
        status: payload.status,
        date: payload.date,
        dateConfirmed: payload.dateConfirmed ?? true,
        timeStatus: payload.timeStatus ?? existing?.timeStatus ?? 'none',
        accountId,
        categoryId: payload.categoryId,
        amount: payload.amount,
        currency: payload.currency,
        toAccountId,
        toAmount: payload.toAmount,
        toCurrency: payload.toCurrency,
        exchangeRate: payload.exchangeRate,
        balanceAfter: payload.balanceAfter,
        recurrenceId: payload.recurrenceId ?? existing?.recurrenceId,
        recurrenceIndex: payload.recurrenceIndex ?? existing?.recurrenceIndex,
        isArchived: payload.isArchived,
        createdAt: payload.createdAt,
        updatedAt: payload.updatedAt,
        seq,
    }

    if (existing) {
        const oldDoc = existing
        await ctx.db.replace(existing._id, doc)
        await aggregateReplace(ctx, oldDoc, existing._id)
    } else {
        const newId = await ctx.db.insert('transactions', doc)
        await aggregateInsert(ctx, newId)
    }
    await clearTombstone(ctx, userId, 'transactions', payload.id)
}

async function applyTransactionTagUpsert(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    payload: TransactionTagUpsert,
): Promise<void> {
    // Defensive ID format check (spec §"Safeguards contra joins duplicados").
    const expected = `${payload.transactionId}__${payload.tagId}`
    if (payload.id !== expected) {
        throw new Error(
            `invalid_join_id: transactionTags.id must equal "<transactionId>__<tagId>" (expected ${expected}, got ${payload.id})`,
        )
    }

    const txn = await ctx.db
        .query('transactions')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.transactionId),
        )
        .unique()
    if (!txn) {
        throw new Error(
            `transactionTag ${payload.id}: transactionId ${payload.transactionId} not found`,
        )
    }
    const tag = await ctx.db
        .query('tags')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.tagId),
        )
        .unique()
    if (!tag) {
        throw new Error(
            `transactionTag ${payload.id}: tagId ${payload.tagId} not found`,
        )
    }

    const existing = await ctx.db
        .query('transactionTags')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.id),
        )
        .unique()

    const doc: Omit<Doc<'transactionTags'>, '_id' | '_creationTime'> = {
        userId,
        id: payload.id,
        transactionId: payload.transactionId,
        tagId: payload.tagId,
        createdAt: payload.createdAt,
        updatedAt: payload.updatedAt,
        seq,
    }
    if (existing) {
        await ctx.db.replace(existing._id, doc)
    } else {
        await ctx.db.insert('transactionTags', doc)
    }
    await clearTombstone(ctx, userId, 'transactionTags', payload.id)
}

async function applySavedFilterUpsert(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    payload: SavedFilterUpsert,
): Promise<void> {
    const existing = await ctx.db
        .query('savedFilters')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.id),
        )
        .unique()
    const doc: Omit<Doc<'savedFilters'>, '_id' | '_creationTime'> = {
        userId,
        id: payload.id,
        name: payload.name,
        config: payload.config,
        isArchived: payload.isArchived,
        createdAt: payload.createdAt,
        updatedAt: payload.updatedAt,
        seq,
    }
    if (existing) {
        await ctx.db.replace(existing._id, doc)
    } else {
        await ctx.db.insert('savedFilters', doc)
    }
    await clearTombstone(ctx, userId, 'savedFilters', payload.id)
}

async function applyDashboardWidgetUpsert(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    payload: DashboardWidgetUpsert,
): Promise<void> {
    // `filterId` is a soft reference — not FK-validated. A widget may arrive in
    // a later chunk than its filter, or reference a filter the user deleted;
    // the client degrades to the match-all filter in that case.
    const existing = await ctx.db
        .query('dashboardWidgets')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.id),
        )
        .unique()
    const doc: Omit<Doc<'dashboardWidgets'>, '_id' | '_creationTime'> = {
        userId,
        id: payload.id,
        type: payload.type,
        filterId: payload.filterId,
        position: payload.position,
        width: payload.width,
        options: payload.options,
        isArchived: payload.isArchived,
        createdAt: payload.createdAt,
        updatedAt: payload.updatedAt,
        seq,
    }
    if (existing) {
        await ctx.db.replace(existing._id, doc)
    } else {
        await ctx.db.insert('dashboardWidgets', doc)
    }
    await clearTombstone(ctx, userId, 'dashboardWidgets', payload.id)
}

async function applyAgentMemoryUpsert(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    payload: AgentMemoryUpsert,
): Promise<void> {
    const existing = await ctx.db
        .query('agentMemories')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.id),
        )
        .unique()
    const doc: Omit<Doc<'agentMemories'>, '_id' | '_creationTime'> = {
        userId,
        id: payload.id,
        content: payload.content,
        isArchived: payload.isArchived,
        createdAt: payload.createdAt,
        updatedAt: payload.updatedAt,
        seq,
    }
    if (existing) {
        await ctx.db.replace(existing._id, doc)
    } else {
        await ctx.db.insert('agentMemories', doc)
    }
    await clearTombstone(ctx, userId, 'agentMemories', payload.id)
}

async function applyRecurrenceUpsert(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    payload: RecurrenceUpsert,
): Promise<void> {
    const existing = await ctx.db
        .query('recurrences')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.id),
        )
        .unique()
    const doc: Omit<Doc<'recurrences'>, '_id' | '_creationTime'> = {
        userId,
        id: payload.id,
        frequency: payload.frequency,
        dayInterval: payload.dayInterval,
        anchorDate: payload.anchorDate,
        endDate: payload.endDate,
        isArchived: payload.isArchived,
        createdAt: payload.createdAt,
        updatedAt: payload.updatedAt,
        seq,
    }
    if (existing) {
        await ctx.db.replace(existing._id, doc)
    } else {
        await ctx.db.insert('recurrences', doc)
    }
    await clearTombstone(ctx, userId, 'recurrences', payload.id)
}

async function applyTombstone(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    args: {
        tableName: SyncedTableName
        entityId: string
        deletedAt: bigint
    },
): Promise<void> {
    // Delete the row if it still exists.
    switch (args.tableName) {
        case 'accounts': {
            const row = await ctx.db
                .query('accounts')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', args.entityId),
                )
                .unique()
            if (row) await ctx.db.delete(row._id)
            break
        }
        case 'categories': {
            const row = await ctx.db
                .query('categories')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', args.entityId),
                )
                .unique()
            if (row) await ctx.db.delete(row._id)
            break
        }
        case 'tags': {
            const row = await ctx.db
                .query('tags')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', args.entityId),
                )
                .unique()
            if (row) await ctx.db.delete(row._id)
            break
        }
        case 'transactions': {
            const row = await ctx.db
                .query('transactions')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', args.entityId),
                )
                .unique()
            if (row) {
                if (row.recurrenceId !== undefined) {
                    // The archived anchor is still the series template. A
                    // legacy delete means this occurrence, not the rule or
                    // the ability to extend its remaining occurrences.
                    await ctx.db.patch(row._id, {
                        isArchived: true,
                        updatedAt: args.deletedAt,
                        seq,
                    })
                    await aggregateReplace(ctx, row, row._id)
                } else {
                    await outflowsByAccount.deleteIfExists(ctx, row)
                    await inflowsByAccount.deleteIfExists(ctx, row)
                    await ctx.db.delete(row._id)
                }
            }
            break
        }
        case 'transactionTags': {
            const row = await ctx.db
                .query('transactionTags')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', args.entityId),
                )
                .unique()
            if (row) await ctx.db.delete(row._id)
            break
        }
        case 'savedFilters': {
            const row = await ctx.db
                .query('savedFilters')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', args.entityId),
                )
                .unique()
            if (row) await ctx.db.delete(row._id)
            break
        }
        case 'dashboardWidgets': {
            const row = await ctx.db
                .query('dashboardWidgets')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', args.entityId),
                )
                .unique()
            if (row) await ctx.db.delete(row._id)
            break
        }
        case 'agentMemories': {
            const row = await ctx.db
                .query('agentMemories')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', args.entityId),
                )
                .unique()
            if (row) await ctx.db.delete(row._id)
            break
        }
        case 'recurrences': {
            const row = await ctx.db
                .query('recurrences')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', args.entityId),
                )
                .unique()
            if (row) await ctx.db.delete(row._id)
            break
        }
    }

    // Upsert the tombstone with the new seq.
    const existing = await ctx.db
        .query('tombstones')
        .withIndex('by_user_table_entity', (q) =>
            q
                .eq('userId', userId)
                .eq('tableName', args.tableName)
                .eq('entityId', args.entityId),
        )
        .unique()
    if (existing) {
        await ctx.db.patch(existing._id, {
            seq,
            deletedAt: args.deletedAt,
        })
    } else {
        await ctx.db.insert('tombstones', {
            userId,
            tableName: args.tableName,
            entityId: args.entityId,
            seq,
            deletedAt: args.deletedAt,
        })
    }
}

export const push = mutation({
    args: {
        expectedServerSeq: v.int64(),
        upserts: v.object({
            accounts: v.optional(v.array(accountUpsert)),
            categories: v.optional(v.array(categoryUpsert)),
            tags: v.optional(v.array(tagUpsert)),
            recurrences: v.optional(v.array(recurrenceUpsert)),
            transactions: v.optional(v.array(transactionUpsert)),
            transactionTags: v.optional(v.array(transactionTagUpsert)),
            savedFilters: v.optional(v.array(savedFilterUpsert)),
            dashboardWidgets: v.optional(v.array(dashboardWidgetUpsert)),
            agentMemories: v.optional(v.array(agentMemoryUpsert)),
        }),
        tombstones: v.optional(v.array(tombstoneArg)),
        platform: v.string(),
        appVersion: v.string(),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)

        // Reject clients below the platform floor before touching any data —
        // this is the write path that would otherwise diverge an incompatible
        // client's rows under LWW (docs/riesgos.md R-008). Fails open for a
        // client that can't report its version (unknown → supported).
        if (!isClientSupported(args.platform, args.appVersion)) {
            return { ok: false as const, error: CLIENT_OUTDATED }
        }

        // 1) CAS
        const counterRow = await ctx.db
            .query('syncCounters')
            .withIndex('by_user', (q) => q.eq('userId', userId))
            .unique()
        const currentCounter = counterRow?.value ?? 0n
        if (currentCounter !== args.expectedServerSeq) {
            return {
                ok: false as const,
                error: 'cursor_mismatch' as const,
                currentCounter,
            }
        }

        // 2) Bump counter.
        const newSeq = currentCounter + 1n
        if (counterRow) {
            await ctx.db.patch(counterRow._id, { value: newSeq })
        } else {
            await ctx.db.insert('syncCounters', { userId, value: newSeq })
        }

        // 3) Apply upserts in catalog-first order. transactionTags depends on
        //    both transactions and tags, so it goes last.
        //
        // Duplicate-name reconciliation (WAL-148) runs once per unique
        // (currency, name) *after* every account upsert in this push has
        // been written — not inline per-upsert — so an in-batch rename swap
        // never sees a transient collision with a sibling row that hasn't
        // reached its final name yet.
        const dirtyAccountKeys = new Map<string, AccountReconcileKey>()
        for (const u of args.upserts.accounts ?? []) {
            const key = await applyAccountUpsert(ctx, userId, newSeq, u)
            if (key) {
                dirtyAccountKeys.set(
                    `${key.currency}\u0000${key.name.trim().toLowerCase()}`,
                    key,
                )
            }
        }
        for (const key of dirtyAccountKeys.values()) {
            await reconcileAccountDuplicates(
                ctx,
                userId,
                newSeq,
                key.currency,
                key.name,
            )
        }
        for (const u of args.upserts.categories ?? []) {
            await applyCategoryUpsert(ctx, userId, newSeq, u)
        }
        for (const u of args.upserts.tags ?? []) {
            await applyTagUpsert(ctx, userId, newSeq, u)
        }
        // Rules before their occurrences: a transaction carries `recurrenceId`.
        for (const u of args.upserts.recurrences ?? []) {
            await applyRecurrenceUpsert(ctx, userId, newSeq, u)
        }
        for (const u of args.upserts.transactions ?? []) {
            await applyTransactionUpsert(ctx, userId, newSeq, u)
        }
        for (const u of args.upserts.transactionTags ?? []) {
            await applyTransactionTagUpsert(ctx, userId, newSeq, u)
        }
        // Saved filters before widgets (a widget's filterId soft-references a
        // saved filter).
        for (const u of args.upserts.savedFilters ?? []) {
            await applySavedFilterUpsert(ctx, userId, newSeq, u)
        }
        for (const u of args.upserts.dashboardWidgets ?? []) {
            await applyDashboardWidgetUpsert(ctx, userId, newSeq, u)
        }
        for (const u of args.upserts.agentMemories ?? []) {
            await applyAgentMemoryUpsert(ctx, userId, newSeq, u)
        }

        // 4) Apply tombstones. transactionTags first so transactions can be
        //    safely deleted without orphaning joins.
        const tombs = args.tombstones ?? []
        const order: Record<(typeof tombs)[number]['tableName'], number> = {
            transactionTags: 0,
            transactions: 1,
            tags: 2,
            categories: 3,
            accounts: 4,
            // Widgets before their saved filters (reverse of upsert order).
            dashboardWidgets: 5,
            savedFilters: 6,
            agentMemories: 7,
            // After transactions: an occurrence still points at the rule, so
            // the rule outlives the rows it owns.
            recurrences: 8,
        }
        const sortedTombs = [...tombs].sort(
            (a, b) => order[a.tableName] - order[b.tableName],
        )
        for (const t of sortedTombs) {
            await applyTombstone(ctx, userId, newSeq, t)
        }

        if (!supportsRecurrences(args.platform, args.appVersion)) {
            const ids = (args.upserts.transactions ?? [])
                .filter((t) => !t.isArchived && t.date >= pastCutoffBigInt())
                .map((t) => t.id)
            if (ids.length)
                await ctx.scheduler.runAfter(
                    0,
                    internal.occurrences.internal.refreshLegacyWrites,
                    { userId, ids },
                )
        }
        return { ok: true as const, newSeq }
    },
})
