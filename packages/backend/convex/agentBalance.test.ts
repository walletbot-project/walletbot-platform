// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import aggregate from '@convex-dev/aggregate/test'
import { convexTest } from 'convex-test'
import { describe, expect, it } from 'vitest'
import { internal } from './_generated/api'
import schema from './schema'
import { aggregateInsert } from './transactions/helpers'

// Lives at the convex root: import.meta.glob keys files in the test's own
// directory as `./x.ts`, which convex-test cannot map back to agent/tools.
const modules = import.meta.glob('./**/*.ts')
const userId = 'agent-balance-user'

// Buenos Aires, UTC-3. 2026-10-03 15:00 local.
const offsetMinutes = -180
const nowMs = Date.UTC(2026, 9, 3, 18, 0)
// Local wall clock in Buenos Aires → epoch.
const local = (day: number, hour: number, minute = 0) =>
    BigInt(Date.UTC(2026, 9, day, hour, minute) - offsetMinutes * 60_000)

async function setup() {
    const t = convexTest(schema, modules)
    aggregate.register(t, 'outflowsByAccount')
    aggregate.register(t, 'inflowsByAccount')
    aggregate.register(t, 'transactionsByTag')
    await t.run(async (ctx) => {
        await ctx.db.insert('accounts', {
            userId,
            id: 'cash',
            name: 'Efectivo',
            currency: 'ARS',
            color: '#000000',
            icon: 'wallet',
            isArchived: false,
            createdAt: 1n,
            updatedAt: 1n,
            seq: 1n,
        })
        const movements: [string, 'income' | 'expense', bigint, bigint][] = [
            // Late on the 1st locally — already the 2nd in UTC.
            ['salary', 'income', 100000n, local(1, 23, 30)],
            // Just after midnight on the 2nd.
            ['coffee', 'expense', 20000n, local(2, 0, 10)],
            // Later today: scheduled, not happened yet.
            ['dinner', 'expense', 5000n, local(3, 20)],
            ['refund', 'income', 500000n, local(4, 10)],
        ]
        for (const [id, type, amount, date] of movements) {
            const inserted = await ctx.db.insert('transactions', {
                userId,
                id,
                type,
                name: id,
                status: 'cleared',
                date,
                dateConfirmed: true,
                accountId: 'cash',
                categoryId: '',
                amount,
                currency: 'ARS',
                isArchived: false,
                createdAt: date,
                updatedAt: date,
                seq: 1n,
            })
            await aggregateInsert(ctx, inserted)
        }
    })

    return async (date?: string) => {
        const raw = await t.mutation(internal.agent.tools.execute, {
            userId,
            name: 'getAccountBalance',
            argsJson: JSON.stringify(
                date === undefined
                    ? { idOrName: 'Efectivo' }
                    : { idOrName: 'Efectivo', date },
            ),
            nowMs,
            utcOffsetMinutes: offsetMinutes,
        })
        return JSON.parse(raw)
    }
}

describe('getAccountBalance with a date', () => {
    it('counts the whole day in the user timezone', async () => {
        const balanceOn = await setup()
        expect(await balanceOn('2026-10-01')).toMatchObject({
            ok: true,
            balance: 1000,
            currency: 'ARS',
            date: '2026-10-01',
        })
        expect((await balanceOn('2026-10-02')).balance).toBe(800)
        expect((await balanceOn('2026-09-30')).balance).toBe(0)
    })

    it('reads today as the current balance', async () => {
        const balanceOn = await setup()
        const current = await balanceOn()
        expect(current.balance).toBe(800)
        expect(current.date).toBeUndefined()
        expect((await balanceOn('hoy')).balance).toBe(800)
    })

    it('counts what is scheduled up to the end of a future day', async () => {
        const balanceOn = await setup()
        expect((await balanceOn('mañana')).balance).toBe(5750)
    })

    it('fails on a date it cannot read', async () => {
        const balanceOn = await setup()
        const result = await balanceOn('not a date').catch((e: Error) => ({
            ok: false,
            error: e.message,
        }))
        expect(result.ok).toBe(false)
    })
})
