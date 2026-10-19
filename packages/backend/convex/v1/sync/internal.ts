import { type Infer, v } from 'convex/values'
import type { Doc } from '../../_generated/dataModel'
import type { MutationCtx } from '../../_generated/server'
import { internalMutation } from '../../_generated/server'
import { inflowsByAccount, outflowsByAccount } from '../../aggregates'
import type {
    syncConflictReason,
    syncConflictResolution,
} from '../../schema/sync'
import { nextSeq } from '../../sync/helpers'
import {
    tagAggregateAttach,
    tagAggregateDeleteTransaction,
    tagAggregateDetach,
} from '../../tags/helpers'
import {
    aggregateInsert,
    aggregateReplace,
    reconcileAfterLedgerChange,
} from '../../transactions/helpers'
import {
    reconcileAccountDuplicates,
    resolveAccountId,
} from '../accounts/helpers'
import { pushTombstones, pushUpserts } from './validators'

// ─────────────────────────────────────────────────────────────────────────────
// Push batch application.
//
// Each push invocation is one chunk = one mutation = one bump of the user's
// counter. `push` (mutations.ts) owns auth, the version floor and the CAS;
// this sub-transaction owns the counter bump and every write, so a throw here
// rolls back the whole batch while `push` still commits its telemetry.
//
// No row the device sends can make the batch throw. A batch that fails is
// retried with the same rows forever and blocks every later change on that
// device, so a row the server can't store as sent is resolved in place: it
// is repaired, replaced by the server's copy, or deleted (see
// `recordConflict`). Whatever the server changed goes out at a later seq
// than the push, because the device acks the push's own seq as known and
// would never pull a change stamped with it. Only a bug still throws.
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

// Deleting an account, category or tag leaves the rows that point at it in
// place: the server hard-deletes the parent but never cascades, and another
// device may have written a child while offline. That child is still the
// user's, and a tombstone scoped to this user proves the parent was too, so
// the reference is kept.
async function wasDeleted(
    ctx: MutationCtx,
    userId: string,
    tableName: SyncedTableName,
    entityId: string,
): Promise<boolean> {
    const tomb = await ctx.db
        .query('tombstones')
        .withIndex('by_user_table_entity', (q) =>
            q
                .eq('userId', userId)
                .eq('tableName', tableName)
                .eq('entityId', entityId),
        )
        .unique()
    return tomb !== null
}

type SyncConflict = {
    tableName: SyncedTableName
    entityId: string
    reason: Infer<typeof syncConflictReason>
    resolution: Infer<typeof syncConflictResolution>
}

// Logs a row the server resolved instead of storing it as sent, and keeps a
// lasting record of it in `syncConflicts`, since a device lost data.
async function recordConflict(
    ctx: MutationCtx,
    userId: string,
    conflict: SyncConflict,
): Promise<void> {
    console.warn('sync conflict resolved', { userId, ...conflict })
    const now = Date.now()
    const existing = await ctx.db
        .query('syncConflicts')
        .withIndex('by_user_table_entity', (q) =>
            q
                .eq('userId', userId)
                .eq('tableName', conflict.tableName)
                .eq('entityId', conflict.entityId),
        )
        .unique()
    if (existing) {
        await ctx.db.patch(existing._id, {
            reason: conflict.reason,
            resolution: conflict.resolution,
            count: existing.count + 1,
            lastSeenAt: now,
        })
    } else {
        await ctx.db.insert('syncConflicts', {
            userId,
            ...conflict,
            count: 1,
            firstSeenAt: now,
            lastSeenAt: now,
        })
    }
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
    // An account's currency is fixed once set, because its movements are in
    // it. A device that sent another one keeps the rest of its edit and gets
    // the stored currency back.
    const currency = existing?.currency ?? payload.currency
    const currencyKept = currency !== payload.currency
    const doc: Omit<Doc<'accounts'>, '_id' | '_creationTime'> = {
        userId,
        id: payload.id,
        name: payload.name,
        currency,
        description: payload.description,
        color: payload.color,
        icon: payload.icon,
        position: payload.position ?? existing?.position,
        isArchived: payload.isArchived,
        createdAt: payload.createdAt,
        updatedAt: payload.updatedAt,
        seq: currencyKept ? await nextSeq(ctx, userId) : seq,
    }
    if (existing) {
        await ctx.db.replace(existing._id, doc)
    } else {
        await ctx.db.insert('accounts', doc)
    }
    await clearTombstone(ctx, userId, 'accounts', payload.id)
    if (currencyKept) {
        await recordConflict(ctx, userId, {
            tableName: 'accounts',
            entityId: payload.id,
            reason: 'account_currency_changed',
            resolution: 'repaired',
        })
    }

    // Name+currency uniqueness (WAL-148) is enforced by merging duplicates
    // rather than rejecting the write — see reconcileAccountDuplicates,
    // called once per unique (currency, name) after every upsert in this
    // push has been applied.
    if (payload.isArchived) return null
    return { currency, name: payload.name }
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

// Why a tag can't keep the parent it was sent with: itself, or a parent
// that is gone (deleted on another device, or never pushed). A parent in
// this same chunk counts as present wherever it sits in the chunk.
async function tagParentConflict(
    ctx: MutationCtx,
    userId: string,
    payload: TagUpsert,
    batchTagIds: ReadonlySet<string>,
): Promise<SyncConflict['reason'] | null> {
    if (!payload.parentId) return null
    if (payload.parentId === payload.id) return 'tag_self_parent'
    if (batchTagIds.has(payload.parentId)) return null
    const parent = await ctx.db
        .query('tags')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.parentId as string),
        )
        .unique()
    return parent ? null : 'tag_parent_missing'
}

async function applyTagUpsert(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    payload: TagUpsert,
    batchTagIds: ReadonlySet<string>,
): Promise<void> {
    // A tag that can't keep its parent moves to the root.
    const parentConflict = await tagParentConflict(
        ctx,
        userId,
        payload,
        batchTagIds,
    )
    const parentId = parentConflict ? undefined : payload.parentId

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
        parentId,
        color: payload.color,
        // A client without positions omits it: keep the stored one, unless
        // the tag moved to another parent, where it no longer applies.
        position: parentConflict
            ? undefined
            : (payload.position ??
              (existing?.parentId === parentId
                  ? existing?.position
                  : undefined)),
        isArchived: payload.isArchived,
        createdAt: payload.createdAt,
        updatedAt: payload.updatedAt,
        seq: parentConflict ? await nextSeq(ctx, userId) : seq,
    }
    if (existing) {
        await ctx.db.replace(existing._id, doc)
    } else {
        await ctx.db.insert('tags', doc)
    }
    await clearTombstone(ctx, userId, 'tags', payload.id)
    if (parentConflict) {
        await recordConflict(ctx, userId, {
            tableName: 'tags',
            entityId: payload.id,
            reason: parentConflict,
            resolution: 'repaired',
        })
    }
}

async function findAccount(
    ctx: MutationCtx,
    userId: string,
    accountId: string,
): Promise<Doc<'accounts'> | null> {
    return await ctx.db
        .query('accounts')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', accountId),
        )
        .unique()
}

// Why a transaction can't be stored as sent, if it can't. An account the
// user never had can't be proven to be theirs, so unlike a deleted one it
// can't be kept as a reference.
async function transactionConflict(
    ctx: MutationCtx,
    userId: string,
    payload: TransactionUpsert,
    accountId: string,
    toAccountId: string | undefined,
): Promise<SyncConflict['reason'] | null> {
    const account = await findAccount(ctx, userId, accountId)
    if (account) {
        if (account.currency !== payload.currency) {
            return 'transaction_currency_mismatch'
        }
    } else if (!(await wasDeleted(ctx, userId, 'accounts', accountId))) {
        return 'transaction_account_missing'
    }

    if (payload.type === 'transfer') {
        if (
            toAccountId === undefined ||
            toAccountId === accountId ||
            payload.toAmount === undefined
        ) {
            return 'transaction_invalid_transfer'
        }
        const toAccount = await findAccount(ctx, userId, toAccountId)
        if (toAccount) {
            if (
                payload.toCurrency &&
                payload.toCurrency !== toAccount.currency
            ) {
                return 'transaction_currency_mismatch'
            }
        } else if (!(await wasDeleted(ctx, userId, 'accounts', toAccountId))) {
            return 'transaction_account_missing'
        }
    }

    if (
        payload.type === 'balance_adjustment' &&
        payload.balanceAfter === undefined
    ) {
        return 'transaction_invalid_adjustment'
    }
    return null
}

// A transaction the server can't store as sent loses the device's change:
// the server's own copy goes back out, or, with no copy to fall back to, the
// row is deleted. The device pulls either over the copy it just acked.
async function rejectTransaction(
    ctx: MutationCtx,
    userId: string,
    payload: TransactionUpsert,
    existing: Doc<'transactions'> | null,
    reason: SyncConflict['reason'],
): Promise<void> {
    const seq = await nextSeq(ctx, userId)
    if (existing) {
        await ctx.db.patch(existing._id, { seq })
    } else {
        await applyTombstone(ctx, userId, seq, {
            tableName: 'transactions',
            entityId: payload.id,
            deletedAt: payload.updatedAt,
        })
    }
    await recordConflict(ctx, userId, {
        tableName: 'transactions',
        entityId: payload.id,
        reason,
        resolution: existing ? 'reverted' : 'dropped',
    })
}

async function applyTransactionUpsert(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    payload: TransactionUpsert,
): Promise<void> {
    const existing = await ctx.db
        .query('transactions')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.id),
        )
        .unique()

    // A merged-away account id (WAL-148 auto-merge) still needs to resolve
    // to its live replacement: a dirty local row created before the device
    // learned about the merge, or a device that hasn't pulled the merge
    // tombstone yet, can otherwise push a reference to an id that no longer
    // exists.
    const accountId = await resolveAccountId(ctx, userId, payload.accountId)
    const toAccountId =
        payload.type === 'transfer' && payload.toAccountId
            ? await resolveAccountId(ctx, userId, payload.toAccountId)
            : undefined

    const conflict = await transactionConflict(
        ctx,
        userId,
        payload,
        accountId,
        toAccountId,
    )
    if (conflict) {
        await rejectTransaction(ctx, userId, payload, existing, conflict)
        return
    }

    // A category the user never had is dropped from the movement, which
    // keeps everything else. A deleted one stays referenced, like an account.
    let categoryId = payload.categoryId
    if (categoryId) {
        const category = await ctx.db
            .query('categories')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', payload.categoryId),
            )
            .unique()
        if (
            !category &&
            !(await wasDeleted(ctx, userId, 'categories', categoryId))
        ) {
            categoryId = ''
            await recordConflict(ctx, userId, {
                tableName: 'transactions',
                entityId: payload.id,
                reason: 'transaction_category_missing',
                resolution: 'repaired',
            })
        }
    }

    // A merge redirect or a dropped category means the server stores what
    // the device didn't send.
    const rewritten =
        accountId !== payload.accountId ||
        (toAccountId !== undefined && toAccountId !== payload.toAccountId) ||
        categoryId !== payload.categoryId

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
        categoryId,
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
        seq: rewritten ? await nextSeq(ctx, userId) : seq,
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

// A join the server can't store is deleted instead, so the device pulls the
// tombstone and drops its own copy.
async function dropTransactionTag(
    ctx: MutationCtx,
    userId: string,
    payload: TransactionTagUpsert,
    reason: SyncConflict['reason'],
): Promise<void> {
    await applyTombstone(ctx, userId, await nextSeq(ctx, userId), {
        tableName: 'transactionTags',
        entityId: payload.id,
        deletedAt: payload.updatedAt,
    })
    await recordConflict(ctx, userId, {
        tableName: 'transactionTags',
        entityId: payload.id,
        reason,
        resolution: 'dropped',
    })
}

async function applyTransactionTagUpsert(
    ctx: MutationCtx,
    userId: string,
    seq: bigint,
    payload: TransactionTagUpsert,
): Promise<void> {
    // Defensive ID format check (spec §"Safeguards contra joins duplicados"):
    // a join under any other id would duplicate the canonical one.
    if (payload.id !== `${payload.transactionId}__${payload.tagId}`) {
        await dropTransactionTag(ctx, userId, payload, 'join_invalid_id')
        return
    }

    // A join can't outlive its transaction or its tag, e.g. one deleted on
    // another device while this one was offline.
    const txn = await ctx.db
        .query('transactions')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.transactionId),
        )
        .unique()
    const tag = await ctx.db
        .query('tags')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', payload.tagId),
        )
        .unique()
    if (!txn || !tag) {
        await dropTransactionTag(ctx, userId, payload, 'join_parent_missing')
        return
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
                    await reconcileAfterLedgerChange(ctx, row, null)
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
                key.currency,
                key.name,
            )
        }
        for (const u of args.upserts.categories ?? []) {
            await applyCategoryUpsert(ctx, userId, newSeq, u)
        }
        const batchTagIds = new Set((args.upserts.tags ?? []).map((u) => u.id))
        for (const u of args.upserts.tags ?? []) {
            await applyTagUpsert(ctx, userId, newSeq, u, batchTagIds)
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
