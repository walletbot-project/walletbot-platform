import { v } from 'convex/values'
import type { Doc, Id } from '../_generated/dataModel'
import type { MutationCtx } from '../_generated/server'
import { mutation } from '../_generated/server'
import { inflowsByAccount, outflowsByAccount } from '../aggregates'
import { nextSeq, writeTombstone } from '../sync/helpers'
import {
    recordMovementCreated,
    recordTransferCreated,
} from '../telemetry/metrics'
import { requireAuth } from '../users/helpers'
import { computeAccountBalance } from './queries'

// ───── Helpers ─────

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

async function aggregateInsert(
    ctx: MutationCtx,
    id: Id<'transactions'>,
): Promise<void> {
    const doc = await ctx.db.get(id)
    if (!doc) return
    await outflowsByAccount.insert(ctx, doc)
    await inflowsByAccount.insert(ctx, doc)
}

async function aggregateReplace(
    ctx: MutationCtx,
    oldDoc: Doc<'transactions'>,
    id: Id<'transactions'>,
): Promise<void> {
    const newDoc = await ctx.db.get(id)
    if (!newDoc) return
    await outflowsByAccount.replace(ctx, oldDoc, newDoc)
    await inflowsByAccount.replace(ctx, oldDoc, newDoc)
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
        status: v.optional(v.union(v.literal('pending'), v.literal('cleared'))),
        createdBy: createdByArg,
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await assertNoExistingId(ctx, userId, args.id)
        assertPositiveAmount(args.amount, 'Amount')

        const account = await getAccount(ctx, userId, args.accountId)
        if (!account) throw new Error('Account not found')
        const category = await getCategory(ctx, userId, args.categoryId)
        if (!category) throw new Error('Category not found')

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        const inserted = await ctx.db.insert('transactions', {
            userId,
            id: args.id,
            type: 'expense',
            name: args.name,
            description: args.description,
            status: args.status ?? 'cleared',
            date: args.date ?? now,
            dateConfirmed: args.dateConfirmed,
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
            tagCount: 0,
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
        status: v.optional(v.union(v.literal('pending'), v.literal('cleared'))),
        createdBy: createdByArg,
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await assertNoExistingId(ctx, userId, args.id)
        assertPositiveAmount(args.amount, 'Amount')

        const account = await getAccount(ctx, userId, args.accountId)
        if (!account) throw new Error('Account not found')
        const category = await getCategory(ctx, userId, args.categoryId)
        if (!category) throw new Error('Category not found')

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        const inserted = await ctx.db.insert('transactions', {
            userId,
            id: args.id,
            type: 'income',
            name: args.name,
            description: args.description,
            status: args.status ?? 'cleared',
            date: args.date ?? now,
            dateConfirmed: args.dateConfirmed,
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
            tagCount: 0,
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
        categoryId: v.string(),
        date: v.optional(v.int64()),
        dateConfirmed: v.boolean(),
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
        const fromAcc = await getAccount(ctx, userId, args.accountId)
        if (!fromAcc) throw new Error('Source account not found')
        const toAcc = await getAccount(ctx, userId, args.toAccountId)
        if (!toAcc) throw new Error('Destination account not found')
        const category = await getCategory(ctx, userId, args.categoryId)
        if (!category) throw new Error('Category not found')

        const sameCurrency = fromAcc.currency === toAcc.currency
        const toAmount =
            args.toAmount ?? (sameCurrency ? args.amount : undefined)
        if (toAmount === undefined) {
            throw new Error(
                'Cross-currency transfers require toAmount (or exchangeRate to derive it)',
            )
        }
        assertPositiveAmount(toAmount, 'Destination amount')

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        const inserted = await ctx.db.insert('transactions', {
            userId,
            id: args.id,
            type: 'transfer',
            name: args.name,
            description: args.description,
            status: args.status ?? 'cleared',
            date: args.date ?? now,
            dateConfirmed: args.dateConfirmed,
            accountId: args.accountId,
            categoryId: args.categoryId,
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
            tagCount: 0,
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
        createdBy: createdByArg,
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await assertNoExistingId(ctx, userId, args.id)

        const account = await getAccount(ctx, userId, args.accountId)
        if (!account) throw new Error('Account not found')

        // Server-side reconciliation: amount = balanceAfter − currentBalance.
        // balanceAfter is the user's observed truth; amount is just the delta
        // the engine needs to make the books match. computeAccountBalance now
        // reads from the aggregate so this is O(log n).
        const currentBalance = await computeAccountBalance(
            ctx,
            userId,
            args.accountId,
        )
        const amount = args.balanceAfter - currentBalance

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        const inserted = await ctx.db.insert('transactions', {
            userId,
            id: args.id,
            type: 'balance_adjustment',
            name: args.name ?? 'Ajuste de saldo',
            description: args.description,
            status: 'cleared',
            date: args.date ?? now,
            dateConfirmed: args.dateConfirmed,
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
            tagCount: 0,
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
        amount: v.optional(v.int64()),
        categoryId: v.optional(v.string()),
        status: v.optional(v.union(v.literal('pending'), v.literal('cleared'))),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await getTransaction(ctx, userId, args.id)
        if (!row) throw new Error('Transaction not found')

        if (args.categoryId !== undefined) {
            const cat = await getCategory(ctx, userId, args.categoryId)
            if (!cat) throw new Error('Category not found')
        }

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        const patch: {
            name?: string
            description?: string
            date?: bigint
            dateConfirmed?: boolean
            amount?: bigint
            categoryId?: string
            status?: 'pending' | 'cleared'
        } = {}
        if (args.name !== undefined) patch.name = args.name
        if (args.description !== undefined) patch.description = args.description
        if (args.date !== undefined) patch.date = args.date
        if (args.dateConfirmed !== undefined)
            patch.dateConfirmed = args.dateConfirmed
        if (args.amount !== undefined) patch.amount = args.amount
        if (args.categoryId !== undefined) patch.categoryId = args.categoryId
        if (args.status !== undefined) patch.status = args.status

        await ctx.db.patch(row._id, { ...patch, updatedAt: now, seq })
        await aggregateReplace(ctx, row, row._id)
    },
})

export const archive = mutation({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await getTransaction(ctx, userId, args.id)
        if (!row) return

        // Detach join rows so tag counts stay accurate.
        const joins = await ctx.db
            .query('transactionTags')
            .withIndex('by_user_transaction', (q) =>
                q.eq('userId', userId).eq('transactionId', args.id),
            )
            .collect()
        for (const j of joins) {
            const jSeq = await nextSeq(ctx, userId)
            await ctx.db.delete(j._id)
            await writeTombstone(ctx, {
                userId,
                tableName: 'transactionTags',
                entityId: j.id,
                seq: jSeq,
            })
        }

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())
        await ctx.db.patch(row._id, {
            isArchived: true,
            updatedAt: now,
            seq,
        })
        // Archived docs contribute 0 to sums (see aggregates.ts). Use replace
        // rather than delete so we retain the entry for potential un-archive.
        await aggregateReplace(ctx, row, row._id)
        await writeTombstone(ctx, {
            userId,
            tableName: 'transactions',
            entityId: args.id,
            seq,
        })
    },
})

// ───── Tag attach / detach ─────

export const tag = mutation({
    args: {
        transactionId: v.string(),
        tagIds: v.array(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const txn = await getTransaction(ctx, userId, args.transactionId)
        if (!txn) throw new Error('Transaction not found')

        let added = 0
        for (const tagId of args.tagIds) {
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
                        .eq('transactionId', args.transactionId)
                        .eq('tagId', tagId),
                )
                .unique()
            if (existing) continue

            const seq = await nextSeq(ctx, userId)
            const now = BigInt(Date.now())
            await ctx.db.insert('transactionTags', {
                userId,
                id: crypto.randomUUID(),
                transactionId: args.transactionId,
                tagId,
                createdAt: now,
                updatedAt: now,
                seq,
            })
            added += 1
        }
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
        let removed = 0
        for (const tagId of args.tagIds) {
            const join = await ctx.db
                .query('transactionTags')
                .withIndex('by_user_transaction_tag', (q) =>
                    q
                        .eq('userId', userId)
                        .eq('transactionId', args.transactionId)
                        .eq('tagId', tagId),
                )
                .unique()
            if (!join) continue

            const seq = await nextSeq(ctx, userId)
            await ctx.db.delete(join._id)
            await writeTombstone(ctx, {
                userId,
                tableName: 'transactionTags',
                entityId: join.id,
                seq,
            })
            removed += 1
        }
        return { removed }
    },
})
