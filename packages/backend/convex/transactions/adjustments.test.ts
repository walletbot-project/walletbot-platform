// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import aggregate from '@convex-dev/aggregate/test'
import { TXN_TYPES, type TxnType } from '@wallet-bot/shared'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { api } from '../_generated/api'
import schema from '../schema'
import { aggregateInsert } from './helpers'

const modules = import.meta.glob('../**/*.ts')
const userId = 'adjustments-user'
const now = Date.UTC(2026, 9, 3, 15, 0)
const DAY = 86_400_000
const modern = { platform: 'android', appVersion: '0.6.0' }

function at(offsetMs: number): bigint {
    return BigInt(now + offsetMs)
}

async function setup() {
    const t = convexTest(schema, modules)
    aggregate.register(t, 'outflowsByAccount')
    aggregate.register(t, 'inflowsByAccount')
    aggregate.register(t, 'transactionsByTag')
    const authed = t.withIdentity({
        subject: userId,
        issuer: 'https://test.convex.site/native-auth',
    })
    await t.run(async (ctx) => {
        for (const id of ['cash', 'bank']) {
            await ctx.db.insert('accounts', {
                userId,
                id,
                name: id,
                currency: 'ARS',
                color: '#000000',
                icon: 'wallet',
                isArchived: false,
                createdAt: 1n,
                updatedAt: 1n,
                seq: 1n,
            })
        }
        await ctx.db.insert('categories', {
            userId,
            id: 'cat',
            name: 'General',
            color: '#000000',
            icon: 'home',
            isArchived: false,
            createdAt: 1n,
            updatedAt: 1n,
            seq: 1n,
        })
        await ctx.db.insert('syncCounters', { userId, value: 1n })
    })

    const amountOf = async (id: string) =>
        (await authed.query(api.v1.transactions.queries.get, { id }))?.amount
    const balanceOf = async (accountId: string) =>
        (
            await authed.query(api.v1.transactions.queries.balance, {
                accountId,
                asOfMs: at(DAY),
            })
        )?.balance

    return { t, authed, amountOf, balanceOf }
}

describe('balance adjustments stay true to their declaration', () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(now)
        vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
    })
    afterEach(() => {
        vi.useRealTimers()
        vi.unstubAllEnvs()
    })

    it('shrinks when a back-dated income is recorded, and grows back when it is deleted', async () => {
        const { authed, amountOf, balanceOf } = await setup()
        await authed.mutation(
            api.v1.transactions.mutations.createBalanceAdjustment,
            {
                id: 'init',
                accountId: 'cash',
                balanceAfter: 200000n,
                name: 'Balance inicial',
                date: at(-3 * DAY),
                dateConfirmed: true,
            },
        )
        await authed.mutation(
            api.v1.transactions.mutations.createBalanceAdjustment,
            {
                id: 'adj',
                accountId: 'cash',
                balanceAfter: 500000n,
                dateConfirmed: true,
            },
        )
        expect(await amountOf('adj')).toBe(300000n)

        // "Yesterday a debt of 1000 was paid back to me."
        await authed.mutation(api.v1.transactions.mutations.createIncome, {
            id: 'debt',
            name: 'Debt paid back',
            amount: 100000n,
            accountId: 'cash',
            categoryId: 'cat',
            date: at(-DAY),
            dateConfirmed: true,
        })
        expect(await amountOf('adj')).toBe(200000n)
        expect(await amountOf('init')).toBe(200000n)
        expect(await balanceOf('cash')).toBe(500000n)

        await authed.mutation(api.v1.transactions.mutations.archive, {
            id: 'debt',
        })
        expect(await amountOf('adj')).toBe(300000n)
        expect(await balanceOf('cash')).toBe(500000n)
    })

    it('ignores movements dated after it', async () => {
        const { authed, amountOf, balanceOf } = await setup()
        await authed.mutation(
            api.v1.transactions.mutations.createBalanceAdjustment,
            {
                id: 'adj',
                accountId: 'cash',
                balanceAfter: 500000n,
                dateConfirmed: true,
            },
        )
        vi.setSystemTime(now + 60_000)
        await authed.mutation(api.v1.transactions.mutations.createExpense, {
            id: 'lunch',
            name: 'Lunch',
            amount: 10000n,
            accountId: 'cash',
            categoryId: 'cat',
            dateConfirmed: true,
        })
        expect(await amountOf('adj')).toBe(500000n)
        expect(await balanceOf('cash')).toBe(490000n)
    })

    it('measures a back-dated declaration against its own date', async () => {
        const { authed, amountOf } = await setup()
        await authed.mutation(api.v1.transactions.mutations.createIncome, {
            id: 'old',
            name: 'Old income',
            amount: 100000n,
            accountId: 'cash',
            categoryId: 'cat',
            date: at(-5 * DAY),
            dateConfirmed: true,
        })
        await authed.mutation(api.v1.transactions.mutations.createExpense, {
            id: 'recent',
            name: 'Recent expense',
            amount: 30000n,
            accountId: 'cash',
            categoryId: 'cat',
            date: at(-DAY),
            dateConfirmed: true,
        })
        // "Three days ago I had 150": only the old income came before it.
        await authed.mutation(
            api.v1.transactions.mutations.createBalanceAdjustment,
            {
                id: 'adj',
                accountId: 'cash',
                balanceAfter: 150000n,
                date: at(-3 * DAY),
                dateConfirmed: true,
            },
        )
        expect(await amountOf('adj')).toBe(50000n)
    })

    it('moves only the first adjustment after an edited movement', async () => {
        const { authed, amountOf } = await setup()
        const declare = (id: string, balanceAfter: bigint, offset: number) =>
            authed.mutation(
                api.v1.transactions.mutations.createBalanceAdjustment,
                {
                    id,
                    accountId: 'cash',
                    balanceAfter,
                    date: at(offset),
                    dateConfirmed: true,
                },
            )
        await declare('first', 100000n, -10 * DAY)
        await declare('second', 300000n, -2 * DAY)
        expect(await amountOf('second')).toBe(200000n)

        await authed.mutation(api.v1.transactions.mutations.createExpense, {
            id: 'spent',
            name: 'Spent',
            amount: 20000n,
            accountId: 'cash',
            categoryId: 'cat',
            date: at(-5 * DAY),
            dateConfirmed: true,
        })
        expect(await amountOf('first')).toBe(100000n)
        expect(await amountOf('second')).toBe(220000n)

        // Moving it before the first declaration hands it to that one instead.
        await authed.mutation(api.v1.transactions.mutations.update, {
            id: 'spent',
            date: at(-20 * DAY),
            dateConfirmed: true,
        })
        expect(await amountOf('first')).toBe(120000n)
        expect(await amountOf('second')).toBe(200000n)
    })

    it('reconciles both accounts of a back-dated transfer', async () => {
        const { authed, amountOf } = await setup()
        for (const [id, accountId, balanceAfter] of [
            ['cash-adj', 'cash', 50000n],
            ['bank-adj', 'bank', 900000n],
        ] as const) {
            await authed.mutation(
                api.v1.transactions.mutations.createBalanceAdjustment,
                { id, accountId, balanceAfter, dateConfirmed: true },
            )
        }
        await authed.mutation(api.v1.transactions.mutations.createTransfer, {
            id: 'withdraw',
            name: 'ATM',
            amount: 20000n,
            accountId: 'bank',
            toAccountId: 'cash',
            date: at(-DAY),
            dateConfirmed: true,
        })
        expect(await amountOf('cash-adj')).toBe(30000n)
        expect(await amountOf('bank-adj')).toBe(920000n)
    })

    it('refuses to edit an adjustment amount or date', async () => {
        const { authed } = await setup()
        await authed.mutation(
            api.v1.transactions.mutations.createBalanceAdjustment,
            {
                id: 'adj',
                accountId: 'cash',
                balanceAfter: 500000n,
                dateConfirmed: true,
            },
        )
        await expect(
            authed.mutation(api.v1.transactions.mutations.update, {
                id: 'adj',
                amount: 1n,
            }),
        ).rejects.toThrow('amount cannot be changed')
        await expect(
            authed.mutation(api.v1.transactions.mutations.update, {
                id: 'adj',
                date: at(-DAY),
                dateConfirmed: true,
            }),
        ).rejects.toThrow('date cannot be changed')
        await authed.mutation(api.v1.transactions.mutations.update, {
            id: 'adj',
            name: 'Counted the drawer',
        })
    })

    it('hands a correction caused by a push back to the pushing device', async () => {
        const { authed, amountOf } = await setup()
        await authed.mutation(
            api.v1.transactions.mutations.createBalanceAdjustment,
            {
                id: 'adj',
                accountId: 'cash',
                balanceAfter: 500000n,
                dateConfirmed: true,
            },
        )
        const counter = await authed.query(api.v1.sync.queries.getCounter, {})
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...modern,
            expectedServerSeq: counter,
            upserts: {
                transactions: [
                    {
                        id: 'offline',
                        type: 'income',
                        name: 'Recorded offline',
                        status: 'cleared',
                        date: at(-DAY),
                        dateConfirmed: true,
                        accountId: 'cash',
                        categoryId: 'cat',
                        amount: 100000n,
                        currency: 'ARS',
                        isArchived: false,
                        createdAt: at(0),
                        updatedAt: at(0),
                    },
                ],
            },
        })
        if (!result.ok) throw new Error(result.error)
        expect(await amountOf('adj')).toBe(400000n)

        // The device acks `newSeq`, so the correction must sit above it.
        const page = await authed.query(api.v1.sync.queries.pull, {
            ...modern,
            since: result.newSeq,
        })
        if ('error' in page) throw new Error(page.error)
        expect(page.rows.find((r) => r.row.id === 'adj')?.row.amount).toBe(
            400000n,
        )
    })

    it('around an adjustment, shows the platform balance it was measured against', async () => {
        const { authed } = await setup()
        await authed.mutation(api.v1.transactions.mutations.createIncome, {
            id: 'salary',
            name: 'Salary',
            amount: 300000n,
            accountId: 'cash',
            categoryId: 'cat',
            date: at(-DAY),
            dateConfirmed: true,
        })
        await authed.mutation(
            api.v1.transactions.mutations.createBalanceAdjustment,
            {
                id: 'adj',
                accountId: 'cash',
                balanceAfter: 500000n,
                dateConfirmed: true,
            },
        )
        expect(
            await authed.query(
                api.v1.transactions.queries.balanceAroundTransaction,
                { transactionId: 'adj', accountId: 'cash' },
            ),
        ).toEqual({ before: 300000n, after: 500000n, currency: 'ARS' })
    })
})

// The backend half of the parity suite in
// packages/shared/src/balance-adjustment-fixtures.json: rows written one at a
// time through the real write path, in any order, must end with the amounts
// the reference replay computes.
type RawEntry = {
    id: string
    type: string
    accountId: string
    toAccountId?: string
    amount: number
    toAmount?: number
    balanceAfter?: number
    date: number
    createdAt: number
    isArchived?: boolean
}
type Fixtures = {
    cases: {
        name: string
        entries: RawEntry[]
        expected: Record<string, number>
    }[]
}

const fixtures: Fixtures = JSON.parse(
    readFileSync(
        resolve(
            import.meta.dirname,
            '../../../shared/src/balance-adjustment-fixtures.json',
        ),
        'utf8',
    ),
)

function isTxnType(value: string): value is TxnType {
    return TXN_TYPES.some((type) => type === value)
}

describe('balance adjustment fixtures, written incrementally', () => {
    for (const fixture of fixtures.cases) {
        for (const [label, order] of [
            ['as listed', fixture.entries],
            ['reversed', [...fixture.entries].reverse()],
        ] as const) {
            it(`${fixture.name} (${label})`, async () => {
                const { t } = await setup()
                await t.run(async (ctx) => {
                    for (const raw of order) {
                        if (!isTxnType(raw.type)) {
                            throw new Error(`unknown type ${raw.type}`)
                        }
                        const id = await ctx.db.insert('transactions', {
                            userId,
                            id: raw.id,
                            type: raw.type,
                            name: raw.id,
                            status: 'cleared',
                            date: BigInt(raw.date),
                            dateConfirmed: true,
                            accountId: raw.accountId,
                            categoryId: '',
                            amount: BigInt(raw.amount),
                            currency: 'ARS',
                            toAccountId: raw.toAccountId,
                            toAmount:
                                raw.toAmount === undefined
                                    ? undefined
                                    : BigInt(raw.toAmount),
                            balanceAfter:
                                raw.balanceAfter === undefined
                                    ? undefined
                                    : BigInt(raw.balanceAfter),
                            isArchived: raw.isArchived ?? false,
                            createdAt: BigInt(raw.createdAt),
                            updatedAt: BigInt(raw.createdAt),
                            seq: 1n,
                        })
                        await aggregateInsert(ctx, id)
                    }
                })
                const amounts = await t.run(async (ctx) => {
                    const result: Record<string, number> = {}
                    for (const id of Object.keys(fixture.expected)) {
                        const row = await ctx.db
                            .query('transactions')
                            .withIndex('by_user_id', (q) =>
                                q.eq('userId', userId).eq('id', id),
                            )
                            .unique()
                        if (row) result[id] = Number(row.amount)
                    }
                    return result
                })
                expect(amounts).toEqual(fixture.expected)
            })
        }
    }
})
