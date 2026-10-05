// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import aggregate from '@convex-dev/aggregate/test'
import { TXN_TYPES, type TxnType } from '@wallet-bot/shared'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { internal } from './_generated/api'
import { inflowsByAccount, outflowsByAccount } from './aggregates'
import schema from './schema'

// Lives at the convex root rather than next to transactions/adjustmentBackfill
// because import.meta.glob keys files in the test's own directory as `./x.ts`,
// which convex-test cannot map back to a function path.
const modules = import.meta.glob('./**/*.ts')
const userId = 'backfill-user'

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
            '../../shared/src/balance-adjustment-fixtures.json',
        ),
        'utf8',
    ),
)

function isTxnType(value: string): value is TxnType {
    return TXN_TYPES.some((type) => type === value)
}

// The one-time backfill: rows written before adjustments became dynamic carry
// stale amounts and were never reconciled. They are inserted here with their
// aggregate entries but without the live reconciliation — the state existing
// deployments are in — and the backfill must bring them to the amounts the
// shared reference computes.
describe('adjustment backfill repairs never-reconciled rows', () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(Date.UTC(2026, 9, 3, 15, 0))
    })
    afterEach(() => {
        vi.useRealTimers()
    })

    for (const fixture of fixtures.cases) {
        it(fixture.name, async () => {
            const t = convexTest(schema, modules)
            aggregate.register(t, 'outflowsByAccount')
            aggregate.register(t, 'inflowsByAccount')
            aggregate.register(t, 'transactionsByTag')

            await t.run(async (ctx) => {
                const accountIds = new Set(
                    fixture.entries.flatMap((e) =>
                        e.toAccountId
                            ? [e.accountId, e.toAccountId]
                            : [e.accountId],
                    ),
                )
                for (const accountId of accountIds) {
                    await ctx.db.insert('accounts', {
                        userId,
                        id: accountId,
                        name: accountId,
                        currency: 'ARS',
                        color: '#000000',
                        icon: 'wallet',
                        isArchived: false,
                        createdAt: 1n,
                        updatedAt: 1n,
                        seq: 1n,
                    })
                }
                for (const raw of fixture.entries) {
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
                    const doc = await ctx.db.get(id)
                    if (!doc) throw new Error('insert failed')
                    await outflowsByAccount.insert(ctx, doc)
                    await inflowsByAccount.insert(ctx, doc)
                }
            })

            const aggregates = await t.query(
                internal.transactions.adjustmentBackfill.verifyAggregates,
                { cursor: null },
            )
            expect(aggregates.mismatches).toEqual([])

            const before = await t.query(
                internal.transactions.adjustmentBackfill.preview,
                { cursor: null },
            )
            expect(before.isDone).toBe(true)

            await t.mutation(internal.transactions.adjustmentBackfill.run, {})
            await t.finishAllScheduledFunctions(vi.runAllTimers)

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

            // The preview predicted exactly the rows the backfill wrote.
            const changedIds = Object.entries(fixture.expected)
                .filter(
                    ([id, cents]) =>
                        fixture.entries.find((e) => e.id === id)?.amount !==
                        cents,
                )
                .map(([id]) => id)
                .sort()
            expect(before.sample.map((c) => c.id).sort()).toEqual(changedIds)

            const after = await t.query(
                internal.transactions.adjustmentBackfill.preview,
                { cursor: null },
            )
            expect(after.wouldChange).toBe(0)
        })
    }
})
