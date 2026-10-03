import { ConvexError, v } from 'convex/values'
import type { Doc } from '../../_generated/dataModel'
import type { MutationCtx } from '../../_generated/server'
import { internalMutation } from '../../_generated/server'
import { inflowsByAccount, outflowsByAccount } from '../../aggregates'
import {
    tagAggregateAttach,
    tagAggregateDeleteTransaction,
    tagAggregateDetach,
} from '../../tags/helpers'
import { aggregateInsert, aggregateReplace } from '../../transactions/helpers'
import {
    reconcileAccountDuplicates,
    resolveAccountId,
} from '../accounts/helpers'
import { pushTombstones, pushUpserts } from './validators'

// Marks the ~15 sync validation throws below (bad currency change, tag
// self-parent, missing account/category, transfer/balance_adjustment
// validation, join-row mismatches) so `push` can classify them as
// `reason: 'validation'` for `sync.errors.count`. A `ConvexError` because
// the throw crosses the `ctx.runMutation` boundary into `push`, and only a
// `ConvexError`'s `data` survives that — a plain subclass's identity doesn't.
export const SYNC_VALIDATION_ERROR = 'sync_validation'
class SyncValidationError extends ConvexError<{
    kind: typeof SYNC_VALIDATION_ERROR
    message: string
}> {
    constructor(message: string) {
        super({ kind: SYNC_VALIDATION_ERROR, message })
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Push batch application.
//
// Each push invocation is one chunk = one mutation = one bump of the user's
// counter. `push` (mutations.ts) owns auth, the version floor and the CAS;
// this sub-transaction owns the counter bump and every write, so a throw here
// rolls back the whole batch while `push` still commits its telemetry.
// ─────────────────────────────────────────────────────────────────────────────

type AccountUpsert = {
    id: string
    name: string
    currency: string
    description?: string
    color: string
    icon: string
    position?: number
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
    position?: number
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
    position?: number
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
        position: payload.position ?? existing?.position,
        isArchived: payload.isArchived,
        createdAt: payload.createdAt,
        updatedAt: payload.updatedAt,
        seq,
    }
    if (existing) {
        if (existing.currency !== payload.currency) {
            throw new SyncValidationError(
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
        position: payload.position ?? existing?.position,
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
        throw new SyncValidationError(
            `tag ${payload.id}: cannot be its own parent`,
        )
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
            throw new SyncValidationError(
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
        // A client without positions omits it: keep the stored one, unless
        // the tag moved to another parent, where it no longer applies.
        position:
            payload.position ??
            (existing?.parentId === payload.parentId
                ? existing?.position
                : undefined),
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
        throw new SyncValidationError(
            `transaction ${payload.id}: accountId ${payload.accountId} not found`,
        )
    }
    if (account.currency !== payload.currency) {
        throw new SyncValidationError(
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
            throw new SyncValidationError(
                `transaction ${payload.id}: categoryId ${payload.categoryId} not found`,
            )
        }
    }

    let toAccountId: string | undefined
    if (payload.type === 'transfer') {
        if (!payload.toAccountId) {
            throw new SyncValidationError(
                `transaction ${payload.id}: transfer requires toAccountId`,
            )
        }
        toAccountId = await resolveAccountId(ctx, userId, payload.toAccountId)
        if (toAccountId === accountId) {
            throw new SyncValidationError(
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
            throw new SyncValidationError(
                `transaction ${payload.id}: toAccountId ${payload.toAccountId} not found`,
            )
        }
        if (payload.toCurrency && payload.toCurrency !== toAcc.currency) {
            throw new SyncValidationError(
                `transaction ${payload.id}: toCurrency ${payload.toCurrency} does not match account ${payload.toAccountId} currency ${toAcc.currency}`,
            )
        }
        if (payload.toAmount === undefined) {
            throw new SyncValidationError(
                `transaction ${payload.id}: transfer requires toAmount`,
            )
        }
    }

    if (payload.type === 'balance_adjustment') {
        if (payload.balanceAfter === undefined) {
            throw new SyncValidationError(
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
        throw new SyncValidationError(
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
        throw new SyncValidationError(
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
        throw new SyncValidationError(
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
    await tagAggregateAttach(ctx, doc, txn)
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
                    await tagAggregateDeleteTransaction(ctx, row)
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
            if (row) {
                await tagAggregateDetach(ctx, row)
                await ctx.db.delete(row._id)
            }
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

export const applyPushBatch = internalMutation({
    args: {
        userId: v.string(),
        currentCounter: v.int64(),
        upserts: pushUpserts,
        tombstones: pushTombstones,
    },
    handler: async (ctx, args): Promise<bigint> => {
        const { userId } = args

        // 2) Bump counter.
        const counterRow = await ctx.db
            .query('syncCounters')
            .withIndex('by_user', (q) => q.eq('userId', userId))
            .unique()
        const newSeq = args.currentCounter + 1n
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

        return newSeq
    },
})
