import { computeExchangeRate } from '@wallet-bot/shared'
import { v } from 'convex/values'
import type { Doc } from '../../_generated/dataModel'
import type { MutationCtx } from '../../_generated/server'
import { mutation } from '../../_generated/server'
import { resolveOccurrenceCutoff } from '../../occurrences/helpers'
import { nextSeq, writeTombstone } from '../../sync/helpers'
import { tagAggregateAttach, tagAggregateDetach } from '../../tags/helpers'
import {
    recordMovementCreated,
    recordTransferCreated,
} from '../../telemetry/metrics'
import {
    aggregateInsert,
    aggregateReplace,
    archiveTransactionRow,
} from '../../transactions/helpers'
import { requireAuth } from '../../users/helpers'
import { computeAccountBalance } from './queries'

// ───── Helpers ─────

const transactionTimeStatus = v.union(
    v.literal('confirmed'),
    v.literal('approximation'),
    v.literal('none'),
)
type TransactionTimeStatus = 'confirmed' | 'approximation' | 'none'

function resolveTimeStatus(
    status: TransactionTimeStatus | undefined,
    date: bigint | undefined,
): TransactionTimeStatus {
    const resolved = status ?? 'none'
    if (resolved !== 'none' && date === undefined) {
        throw new Error(`date is required when timeStatus is ${resolved}`)
    }
    return resolved
}

const createdByArg = v.optional(v.union(v.literal('form'), v.literal('agent')))

async function getAccount(
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

async function getCategory(
    ctx: MutationCtx,
    userId: string,
    categoryId: string,
): Promise<Doc<'categories'> | null> {
    return await ctx.db
        .query('categories')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', userId).eq('id', categoryId),
        )
        .unique()
}

async function getTransaction(
    ctx: MutationCtx,
    userId: string,
    id: string,
): Promise<Doc<'transactions'> | null> {
    return await ctx.db
        .query('transactions')
        .withIndex('by_user_id', (q) => q.eq('userId', userId).eq('id', id))
        .unique()
}

async function assertNoExistingId(
    ctx: MutationCtx,
    userId: string,
    id: string,
): Promise<void> {
    const existing = await getTransaction(ctx, userId, id)
    if (existing) throw new Error('Transaction with that id already exists')
}

function assertPositiveAmount(amount: bigint, label: string): void {
    if (amount <= 0n) {
        throw new Error(`${label} must be greater than 0`)
    }
}

// ───── Creates ─────

export const createExpense = mutation({
    args: {
        id: v.string(),
        name: v.string(),
        description: v.optional(v.string()),
        amount: v.int64(), // cents
        accountId: v.string(),
        categoryId: v.string(),
        date: v.optional(v.int64()),
        dateConfirmed: v.boolean(),
        timeStatus: v.optional(transactionTimeStatus),
        status: v.optional(v.union(v.literal('pending'), v.literal('cleared'))),
        createdBy: createdByArg,
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await assertNoExistingId(ctx, userId, args.id)
        assertPositiveAmount(args.amount, 'Amount')

        // Archived accounts/categories are not valid targets for a new
        // movement — same rule the native local write enforces.
        const account = await getAccount(ctx, userId, args.accountId)
        if (!account || account.isArchived) {
            throw new Error('Account not found')
        }
        const category = await getCategory(ctx, userId, args.categoryId)
        if (!category || category.isArchived) {
            throw new Error('Category not found')
        }

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())
        const timeStatus = resolveTimeStatus(args.timeStatus, args.date)

        const inserted = await ctx.db.insert('transactions', {
            userId,
            id: args.id,
            type: 'expense',
            name: args.name,
            description: args.description,
            status: args.status ?? 'cleared',
            date: args.date ?? now,
            dateConfirmed: args.dateConfirmed,
            timeStatus,
            accountId: args.accountId,
            categoryId: args.categoryId,
            amount: args.amount,
            currency: account.currency,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq,
        })
        await aggregateInsert(ctx, inserted)
        await recordMovementCreated(ctx, {
            userId,
            movementType: 'expense',
            createdBy: args.createdBy ?? 'form',
            ingestPath: 'direct_mutation',
        })
        return args.id
    },
})

export const createIncome = mutation({
    args: {
        id: v.string(),
        name: v.string(),
        description: v.optional(v.string()),
        amount: v.int64(),
        accountId: v.string(),
        categoryId: v.string(),
        date: v.optional(v.int64()),
        dateConfirmed: v.boolean(),
        timeStatus: v.optional(transactionTimeStatus),
        status: v.optional(v.union(v.literal('pending'), v.literal('cleared'))),
        createdBy: createdByArg,
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await assertNoExistingId(ctx, userId, args.id)
        assertPositiveAmount(args.amount, 'Amount')

        // Archived accounts/categories are not valid targets for a new
        // movement — same rule the native local write enforces.
        const account = await getAccount(ctx, userId, args.accountId)
        if (!account || account.isArchived) {
            throw new Error('Account not found')
        }
        const category = await getCategory(ctx, userId, args.categoryId)
        if (!category || category.isArchived) {
            throw new Error('Category not found')
        }

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())
        const timeStatus = resolveTimeStatus(args.timeStatus, args.date)

        const inserted = await ctx.db.insert('transactions', {
            userId,
            id: args.id,
            type: 'income',
            name: args.name,
            description: args.description,
            status: args.status ?? 'cleared',
            date: args.date ?? now,
            dateConfirmed: args.dateConfirmed,
            timeStatus,
            accountId: args.accountId,
            categoryId: args.categoryId,
            amount: args.amount,
            currency: account.currency,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq,
        })
        await aggregateInsert(ctx, inserted)
        await recordMovementCreated(ctx, {
            userId,
            movementType: 'income',
            createdBy: args.createdBy ?? 'form',
            ingestPath: 'direct_mutation',
        })
        return args.id
    },
})

export const createTransfer = mutation({
    args: {
        id: v.string(),
        name: v.string(),
        description: v.optional(v.string()),
        amount: v.int64(),
        accountId: v.string(),
        toAccountId: v.string(),
        toAmount: v.optional(v.int64()),
        exchangeRate: v.optional(v.number()),
        // Optional: transfers move money between the user's own accounts and
        // are excluded from category breakdowns, so a category is decoration.
        // Stored as '' when absent — the same representation the native app
        // and the sync wire already use for a category-less transfer.
        categoryId: v.optional(v.string()),
        date: v.optional(v.int64()),
        dateConfirmed: v.boolean(),
        timeStatus: v.optional(transactionTimeStatus),
        status: v.optional(v.union(v.literal('pending'), v.literal('cleared'))),
        createdBy: createdByArg,
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await assertNoExistingId(ctx, userId, args.id)
        assertPositiveAmount(args.amount, 'Amount')

        if (args.accountId === args.toAccountId) {
            throw new Error('Source and destination accounts must differ')
        }
        // Archived accounts/categories are not valid targets for a new
        // movement — same rule the native local write enforces.
        const fromAcc = await getAccount(ctx, userId, args.accountId)
        if (!fromAcc || fromAcc.isArchived) {
            throw new Error('Source account not found')
        }
        const toAcc = await getAccount(ctx, userId, args.toAccountId)
        if (!toAcc || toAcc.isArchived) {
            throw new Error('Destination account not found')
        }
        if (args.categoryId) {
            const category = await getCategory(ctx, userId, args.categoryId)
            if (!category || category.isArchived) {
                throw new Error('Category not found')
            }
        }

        const sameCurrency = fromAcc.currency === toAcc.currency
        const toAmount =
            args.toAmount ?? (sameCurrency ? args.amount : undefined)
        if (toAmount === undefined) {
            throw new Error(
                'Cross-currency transfers require toAmount (the amount received on the destination side)',
            )
        }
        assertPositiveAmount(toAmount, 'Destination amount')

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())
        const timeStatus = resolveTimeStatus(args.timeStatus, args.date)

        const inserted = await ctx.db.insert('transactions', {
            userId,
            id: args.id,
            type: 'transfer',
            name: args.name,
            description: args.description,
            status: args.status ?? 'cleared',
            date: args.date ?? now,
            dateConfirmed: args.dateConfirmed,
            timeStatus,
            accountId: args.accountId,
            categoryId: args.categoryId ?? '',
            amount: args.amount,
            currency: fromAcc.currency,
            toAccountId: args.toAccountId,
            toAmount,
            toCurrency: toAcc.currency,
            exchangeRate: args.exchangeRate,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq,
        })
        await aggregateInsert(ctx, inserted)
        await recordTransferCreated(ctx, {
            userId,
            createdBy: args.createdBy ?? 'form',
            ingestPath: 'direct_mutation',
            crossCurrency: !sameCurrency,
        })
        return args.id
    },
})

export const createBalanceAdjustment = mutation({
    args: {
        id: v.string(),
        accountId: v.string(),
        balanceAfter: v.int64(), // cents — sacred, server never modifies this
        name: v.optional(v.string()),
        description: v.optional(v.string()),
        date: v.optional(v.int64()),
        dateConfirmed: v.boolean(),
        timeStatus: v.optional(transactionTimeStatus),
        createdBy: createdByArg,
        asOfMs: v.optional(v.int64()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const asOfMs = resolveOccurrenceCutoff(args.asOfMs)
        await assertNoExistingId(ctx, userId, args.id)

        const account = await getAccount(ctx, userId, args.accountId)
        if (!account) throw new Error('Account not found')

        // Server-side reconciliation: amount = balanceAfter − currentBalance.
        // balanceAfter is the user's observed truth; amount is just the delta
        // the engine needs to make the books match. computeAccountBalance now
        // reads from the aggregate so this is O(log n).
        //
        // The balance being reconciled against is the one the user can see, so
        // it stops at the occurrence cutoff: a movement scheduled for next
        // month must not change what "my balance is X right now" means.
        const currentBalance = await computeAccountBalance(
            ctx,
            userId,
            args.accountId,
            asOfMs,
        )
        const amount = args.balanceAfter - currentBalance

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())
        const timeStatus = resolveTimeStatus(args.timeStatus, args.date)

        const inserted = await ctx.db.insert('transactions', {
            userId,
            id: args.id,
            type: 'balance_adjustment',
            name: args.name ?? 'Ajuste de saldo',
            description: args.description,
            status: 'cleared',
            date: args.date ?? now,
            dateConfirmed: args.dateConfirmed,
            timeStatus,
            accountId: args.accountId,
            categoryId: '',
            amount,
            currency: account.currency,
            balanceAfter: args.balanceAfter,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq,
        })
        await aggregateInsert(ctx, inserted)
        await recordMovementCreated(ctx, {
            userId,
            movementType: 'balance_adjustment',
            createdBy: args.createdBy ?? 'form',
            ingestPath: 'direct_mutation',
        })
        return args.id
    },
})

// ───── Update / Delete ─────

export const update = mutation({
    args: {
        id: v.string(),
        name: v.optional(v.string()),
        description: v.optional(v.string()),
        date: v.optional(v.int64()),
        dateConfirmed: v.optional(v.boolean()),
        timeStatus: v.optional(transactionTimeStatus),
        amount: v.optional(v.int64()),
        accountId: v.optional(v.string()),
        toAccountId: v.optional(v.string()),
        toAmount: v.optional(v.int64()),
        categoryId: v.optional(v.string()),
        status: v.optional(v.union(v.literal('pending'), v.literal('cleared'))),
        addTagIds: v.optional(v.array(v.string())),
        removeTagIds: v.optional(v.array(v.string())),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await getTransaction(ctx, userId, args.id)
        if (!row) throw new Error('Transaction not found')

        if (args.categoryId !== undefined) {
            const cat = await getCategory(ctx, userId, args.categoryId)
            if (!cat) throw new Error('Category not found')
        }

        if (args.amount !== undefined)
            assertPositiveAmount(args.amount, 'Amount')
        if (args.toAmount !== undefined)
            assertPositiveAmount(args.toAmount, 'Destination amount')

        if (
            row.type !== 'transfer' &&
            (args.toAccountId !== undefined || args.toAmount !== undefined)
        ) {
            throw new Error(
                'Destination account and amount can only be changed on transfers',
            )
        }
        if (row.type === 'balance_adjustment' && args.accountId !== undefined) {
            throw new Error('Balance adjustment account cannot be changed')
        }

        const nextAccountId = args.accountId ?? row.accountId
        const sourceAccount = await getAccount(ctx, userId, nextAccountId)
        if (!sourceAccount) throw new Error('Account not found')

        const nextToAccountId = args.toAccountId ?? row.toAccountId
        const destinationAccount =
            row.type === 'transfer' && nextToAccountId !== undefined
                ? await getAccount(ctx, userId, nextToAccountId)
                : null
        if (row.type === 'transfer') {
            if (!destinationAccount)
                throw new Error('Destination account not found')
            if (nextAccountId === nextToAccountId) {
                throw new Error('Source and destination accounts must differ')
            }
        }

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        const patch: {
            name?: string
            description?: string
            date?: bigint
            dateConfirmed?: boolean
            timeStatus?: TransactionTimeStatus
            amount?: bigint
            accountId?: string
            currency?: string
            toAccountId?: string
            toAmount?: bigint
            toCurrency?: string
            exchangeRate?: number
            categoryId?: string
            status?: 'pending' | 'cleared'
        } = {}
        if (args.name !== undefined) patch.name = args.name
        if (args.description !== undefined) patch.description = args.description
        if (args.date !== undefined) patch.date = args.date
        if (args.dateConfirmed !== undefined)
            patch.dateConfirmed = args.dateConfirmed
        if (args.timeStatus !== undefined) {
            if (args.timeStatus !== 'none' && args.date === undefined) {
                throw new Error(
                    `date is required when timeStatus is ${args.timeStatus}`,
                )
            }
            patch.timeStatus = args.timeStatus
        }
        if (args.accountId !== undefined) {
            patch.accountId = args.accountId
            patch.currency = sourceAccount.currency
        }
        if (args.toAccountId !== undefined) {
            patch.toAccountId = args.toAccountId
            patch.toCurrency = destinationAccount!.currency
        }

        if (row.type === 'transfer') {
            const sameCurrency =
                sourceAccount.currency === destinationAccount!.currency
            let nextAmount = args.amount ?? row.amount
            let nextToAmount = args.toAmount ?? row.toAmount ?? row.amount

            if (sameCurrency) {
                if (args.toAmount !== undefined && args.amount === undefined) {
                    nextAmount = args.toAmount
                }
                nextToAmount = nextAmount
            }

            if (args.amount !== undefined || nextAmount !== row.amount) {
                patch.amount = nextAmount
            }
            if (
                args.toAmount !== undefined ||
                args.amount !== undefined ||
                args.accountId !== undefined ||
                args.toAccountId !== undefined
            ) {
                patch.toAmount = nextToAmount
                patch.exchangeRate = sameCurrency
                    ? undefined
                    : computeExchangeRate(
                          Number(nextAmount),
                          Number(nextToAmount),
                      )
            }
        } else if (args.amount !== undefined) {
            patch.amount = args.amount
        }
        if (args.categoryId !== undefined) patch.categoryId = args.categoryId
        if (args.status !== undefined) patch.status = args.status

        await ctx.db.patch(row._id, { ...patch, updatedAt: now, seq })
        await aggregateReplace(ctx, row, row._id)

        // Tag changes ride in the same mutation so the edit and its tags commit
        // atomically — a failing tag change rolls back the whole update instead
        // of leaving a partially saved transaction.
        if (args.removeTagIds && args.removeTagIds.length > 0) {
            await detachTags(ctx, userId, args.id, args.removeTagIds)
        }
        if (args.addTagIds && args.addTagIds.length > 0) {
            await attachTags(ctx, userId, args.id, args.addTagIds)
        }
    },
})

export const archive = mutation({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await getTransaction(ctx, userId, args.id)
        if (!row) return
        await archiveTransactionRow(ctx, userId, row)
    },
})

// ───── Tag attach / detach ─────

// Shared attach/detach used by the `tag`/`untag` mutations and by `update` so a
// transaction edit and its tag changes commit atomically in one mutation.
export async function attachTags(
    ctx: MutationCtx,
    userId: string,
    transactionId: string,
    tagIds: string[],
): Promise<number> {
    let added = 0
    for (const tagId of tagIds) {
        const tagRow = await ctx.db
            .query('tags')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', tagId),
            )
            .unique()
        if (!tagRow || tagRow.isArchived) continue

        const existing = await ctx.db
            .query('transactionTags')
            .withIndex('by_user_transaction_tag', (q) =>
                q
                    .eq('userId', userId)
                    .eq('transactionId', transactionId)
                    .eq('tagId', tagId),
            )
            .unique()
        if (existing) continue

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())
        const join = {
            userId,
            id: crypto.randomUUID(),
            transactionId,
            tagId,
            createdAt: now,
            updatedAt: now,
            seq,
        }
        await ctx.db.insert('transactionTags', join)
        await tagAggregateAttach(ctx, join)
        added += 1
    }
    return added
}

export async function detachTags(
    ctx: MutationCtx,
    userId: string,
    transactionId: string,
    tagIds: string[],
): Promise<number> {
    let removed = 0
    for (const tagId of tagIds) {
        const join = await ctx.db
            .query('transactionTags')
            .withIndex('by_user_transaction_tag', (q) =>
                q
                    .eq('userId', userId)
                    .eq('transactionId', transactionId)
                    .eq('tagId', tagId),
            )
            .unique()
        if (!join) continue

        const seq = await nextSeq(ctx, userId)
        await tagAggregateDetach(ctx, join)
        await ctx.db.delete(join._id)
        await writeTombstone(ctx, {
            userId,
            tableName: 'transactionTags',
            entityId: join.id,
            seq,
        })
        removed += 1
    }
    return removed
}

export const tag = mutation({
    args: {
        transactionId: v.string(),
        tagIds: v.array(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const txn = await getTransaction(ctx, userId, args.transactionId)
        if (!txn) throw new Error('Transaction not found')

        const added = await attachTags(
            ctx,
            userId,
            args.transactionId,
            args.tagIds,
        )
        return { added }
    },
})

export const untag = mutation({
    args: {
        transactionId: v.string(),
        tagIds: v.array(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const removed = await detachTags(
            ctx,
            userId,
            args.transactionId,
            args.tagIds,
        )
        return { removed }
    },
})
