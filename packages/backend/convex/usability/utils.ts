import { adjustmentAmount } from '@wallet-bot/shared'
import type { Doc } from '../_generated/dataModel'
import type { MutationCtx } from '../_generated/server'
import { nextSeq } from '../sync/helpers'
import { tagAggregateAttach } from '../tags/helpers'
import { aggregateInsert, balanceBeforeInLedger } from '../transactions/helpers'
import {
    exchangeRateFor,
    type PlanTransaction,
    type UsabilityPlan,
} from './datasets'

export type PlanIds = Record<string, string>

const PASSWORD_ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789'

export function randomCode(length: number): string {
    const bytes = new Uint8Array(length)
    crypto.getRandomValues(bytes)
    return Array.from(
        bytes,
        (byte) => PASSWORD_ALPHABET[byte % PASSWORD_ALPHABET.length],
    ).join('')
}

export function testUserEmail(
    number: number,
    scenario: number,
    tag: string,
): string {
    return `p${String(number).padStart(2, '0')}-e${scenario}-${tag}@walletbot.test`
}

export function testUserName(number: number, scenario: number): string {
    return `P${String(number).padStart(2, '0')} Escenario ${scenario}`
}

function entityId(ids: PlanIds, kind: string, key: string): string {
    const id = ids[`${kind}:${key}`]
    if (!id) throw new Error(`Missing ${kind} ${key} in the generated plan`)
    return id
}

/**
 * Writes a plan's accounts, categories, tags and recurring rules the way the
 * v1 create mutations do, and returns the ids its transactions refer to.
 */
export async function insertPlanEntities(
    ctx: MutationCtx,
    userId: string,
    plan: UsabilityPlan,
): Promise<PlanIds> {
    const ids: PlanIds = {}
    const now = BigInt(Date.now())
    for (const [position, account] of plan.accounts.entries()) {
        const id = crypto.randomUUID()
        ids[`account:${account.key}`] = id
        await ctx.db.insert('accounts', {
            userId,
            id,
            name: account.name,
            currency: account.currency,
            color: account.color,
            icon: account.icon,
            position,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq: await nextSeq(ctx, userId),
        })
    }
    for (const [position, category] of plan.categories.entries()) {
        const id = crypto.randomUUID()
        ids[`category:${category.key}`] = id
        await ctx.db.insert('categories', {
            userId,
            id,
            name: category.name,
            color: category.color,
            icon: category.icon,
            position,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq: await nextSeq(ctx, userId),
        })
    }
    for (const [position, tag] of plan.tags.entries()) {
        const id = crypto.randomUUID()
        ids[`tag:${tag.key}`] = id
        await ctx.db.insert('tags', {
            userId,
            id,
            name: tag.name,
            color: tag.color,
            position,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq: await nextSeq(ctx, userId),
        })
    }
    for (const rule of plan.recurrences) {
        const id = crypto.randomUUID()
        ids[`recurrence:${rule.key}`] = id
        await ctx.db.insert('recurrences', {
            userId,
            id,
            frequency: 'monthly',
            anchorDate: BigInt(rule.anchorMs),
            endDate: rule.endMs === undefined ? undefined : BigInt(rule.endMs),
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq: await nextSeq(ctx, userId),
        })
    }
    return ids
}

/**
 * Inserts one planned movement with everything the v1 mutations attach to a
 * write: a fresh sync seq, the balance and tag aggregates, and canonical tag
 * join ids.
 */
export async function insertPlanTransaction(
    ctx: MutationCtx,
    userId: string,
    plan: UsabilityPlan,
    ids: PlanIds,
    txn: PlanTransaction,
): Promise<void> {
    const account = plan.accounts.find((item) => item.key === txn.accountKey)
    if (!account) throw new Error(`Unknown account ${txn.accountKey}`)
    const accountId = entityId(ids, 'account', txn.accountKey)
    const id = crypto.randomUUID()
    const now = BigInt(Date.now())
    const date = BigInt(txn.dateMs)

    const doc: Omit<Doc<'transactions'>, '_id' | '_creationTime'> = {
        userId,
        id,
        type: txn.type,
        name: txn.name,
        status: 'cleared',
        date,
        dateConfirmed: true,
        timeStatus: 'none',
        accountId,
        categoryId: txn.categoryKey
            ? entityId(ids, 'category', txn.categoryKey)
            : '',
        amount: BigInt(txn.amountCents),
        currency: account.currency,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        seq: await nextSeq(ctx, userId),
    }

    if (txn.type === 'transfer') {
        const destination = plan.accounts.find(
            (item) => item.key === txn.toAccountKey,
        )
        if (!destination || !txn.toAccountKey) {
            throw new Error(`Unknown account ${txn.toAccountKey}`)
        }
        doc.toAccountId = entityId(ids, 'account', txn.toAccountKey)
        doc.toAmount = BigInt(txn.toAmountCents ?? txn.amountCents)
        doc.toCurrency = destination.currency
        doc.exchangeRate = exchangeRateFor(txn)
    }

    if (txn.type === 'balance_adjustment') {
        const balanceAfter = BigInt(txn.amountCents)
        const previous = await balanceBeforeInLedger(ctx, userId, accountId, {
            id,
            type: 'balance_adjustment',
            accountId,
            amount: 0n,
            balanceAfter,
            date,
            createdAt: now,
            isArchived: false,
        })
        doc.balanceAfter = balanceAfter
        doc.amount = adjustmentAmount(balanceAfter, previous)
    }

    if (txn.recurrence) {
        doc.recurrenceId = entityId(ids, 'recurrence', txn.recurrence.key)
        doc.recurrenceIndex = BigInt(txn.recurrence.index)
    }

    const inserted = await ctx.db.insert('transactions', doc)
    await aggregateInsert(ctx, inserted)

    for (const tagKey of txn.tagKeys ?? []) {
        const tagId = entityId(ids, 'tag', tagKey)
        const join = {
            userId,
            id: `${id}__${tagId}`,
            transactionId: id,
            tagId,
            createdAt: now,
            updatedAt: now,
            seq: await nextSeq(ctx, userId),
        }
        await ctx.db.insert('transactionTags', join)
        await tagAggregateAttach(ctx, join)
    }
}
