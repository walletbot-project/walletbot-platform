// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import aggregate from '@convex-dev/aggregate/test'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { api, internal } from '../_generated/api'
import { isClientSupported } from '../config/helpers'
import schema from '../schema'
import { aggregateInsert } from '../transactions/helpers'

const modules = import.meta.glob('../**/*.ts')
const now = Date.UTC(2026, 8, 13, 12, 0)
const modern = { platform: 'android', appVersion: '0.6.0' }
const userId = 'compatibility-user'

async function fixture() {
    const t = convexTest(schema, modules)
    aggregate.register(t, 'outflowsByAccount')
    aggregate.register(t, 'inflowsByAccount')
    aggregate.register(t, 'transactionsByTag')
    aggregate.register(t, 'latencyByOperation')
    const authed = t.withIdentity({
        subject: userId,
        issuer: 'https://test.convex.site/native-auth',
    })
    await t.run(async (ctx) => {
        await ctx.db.insert('accounts', {
            userId,
            id: 'a',
            name: 'Cash',
            currency: 'ARS',
            color: '#000000',
            icon: 'wallet',
            isArchived: false,
            createdAt: 1n,
            updatedAt: 1n,
            seq: 1n,
        })
        await ctx.db.insert('categories', {
            userId,
            id: 'c',
            name: 'Rent',
            color: '#000000',
            icon: 'home',
            isArchived: false,
            createdAt: 1n,
            updatedAt: 1n,
            seq: 2n,
        })
        await ctx.db.insert('recurrences', {
            userId,
            id: 'r',
            frequency: 'monthly',
            anchorDate: BigInt(now - 1000),
            isArchived: false,
            createdAt: 1n,
            updatedAt: 1n,
            seq: 3n,
        })
        for (const [index, date] of [now - 1000, now + 3600000].entries()) {
            const id = await ctx.db.insert('transactions', {
                userId,
                id: `t${index}`,
                type: 'expense',
                name: 'Rent',
                status: 'cleared',
                date: BigInt(date),
                dateConfirmed: true,
                timeStatus: 'none',
                accountId: 'a',
                categoryId: 'c',
                currency: 'ARS',
                amount: 10000n,
                recurrenceId: 'r',
                recurrenceIndex: BigInt(index),
                isArchived: false,
                createdAt: 1n,
                updatedAt: 10n,
                seq: BigInt(4 + index),
            })
            await aggregateInsert(ctx, id)
        }
        await ctx.db.insert('tags', {
            userId,
            id: 'tag',
            name: 'Monthly',
            color: '#000000',
            isArchived: false,
            createdAt: 1n,
            updatedAt: 1n,
            seq: 6n,
        })
        await ctx.db.insert('transactionTags', {
            userId,
            id: 't1__tag',
            transactionId: 't1',
            tagId: 'tag',
            createdAt: 1n,
            updatedAt: 2n,
            seq: 7n,
        })
        await ctx.db.insert('syncCounters', { userId, value: 7n })
    })
    return { t, authed }
}

describe('legacy recurrence compatibility', { timeout: 30000 }, () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(now)
        vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
    })
    afterEach(() => {
        vi.useRealTimers()
        vi.unstubAllEnvs()
    })

    it('requires 0.6.0 on every native platform', () => {
        for (const platform of ['android', 'ios', 'macos']) {
            expect(isClientSupported(platform, '0.6.0')).toBe(true)
            expect(isClientSupported(platform, '0.5.1')).toBe(false)
        }
    })

    it('supports old web arguments and excludes future installments from totals', async () => {
        const { authed } = await fixture()
        expect(
            (await authed.query(api.v1.transactions.queries.recent, {})).map(
                (t) => t.id,
            ),
        ).toEqual(['t0'])
        expect(
            await authed.query(api.v1.transactions.queries.balance, {
                accountId: 'a',
            }),
        ).toEqual({ balance: -10000n, currency: 'ARS' })
        expect(
            (
                await authed.query(api.v1.transactions.queries.listPaginated, {
                    paginationOpts: { numItems: 10, cursor: null },
                })
            ).page.map((t) => t.id),
        ).toEqual(['t0'])
        expect(
            (
                await authed.query(
                    api.v1.categories.queries.listActiveWithCounts,
                    {},
                )
            )[0].transactionCount,
        ).toBe(1)
        expect(
            (
                await authed.query(api.v1.tags.queries.listActiveWithCounts, {})
            )[0].transactionCount,
        ).toBe(0)
        expect(
            await authed.query(api.v1.dashboard.queries.currencyBalance, {
                currency: 'ARS',
            }),
        ).toEqual({ balance: -10000n, accountCount: 1 })
        await authed.mutation(
            api.v1.transactions.mutations.createBalanceAdjustment,
            {
                id: 'adjust',
                accountId: 'a',
                balanceAfter: 50000n,
                dateConfirmed: true,
                createdBy: 'form',
            },
        )
        expect(
            await authed.query(api.v1.transactions.queries.balance, {
                accountId: 'a',
            }),
        ).toMatchObject({ balance: 50000n })
    })

    it('accepts retired development metadata without leaking it to clients or using its clock', async () => {
        const { t, authed } = await fixture()
        await t.run(async (ctx) => {
            const row = await ctx.db
                .query('transactions')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', 't1'),
                )
                .unique()
            if (!row) throw new Error('missing fixture')
            await ctx.db.patch(row._id, { legacyPendingDate: row.date })
            await ctx.db.insert('occurrenceClock', {
                key: 'singleton',
                cutoff: 1n,
            })
        })
        const page = await authed.query(api.v1.sync.queries.pull, {
            ...modern,
            since: 0n,
        })
        if ('error' in page) throw new Error(page.error)
        expect(page.rows.every((r) => !('legacyPendingDate' in r.row))).toBe(
            true,
        )
        expect(
            await authed.query(api.v1.transactions.queries.recent, {}),
        ).toHaveLength(1)
        vi.setSystemTime(now + 3600000)
        expect(
            await authed.query(api.v1.transactions.queries.recent, {}),
        ).toHaveLength(2)
    })
})

describe('WhatsApp with recurrence-aware and legacy clients', {
    timeout: 60000,
}, () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(now)
        vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
    })
    afterEach(() => {
        vi.useRealTimers()
        vi.unstubAllEnvs()
    })

    async function execute(
        t: Awaited<ReturnType<typeof fixture>>['t'],
        name: string,
        args: Record<string, unknown>,
    ): Promise<Record<string, unknown>> {
        return JSON.parse(
            await t.mutation(internal.agent.tools.execute, {
                userId,
                name,
                argsJson: JSON.stringify(args),
                nowMs: now,
                utcOffsetMinutes: 0,
            }),
        )
    }

    it('rejects unsupported series writes before modifying financial data', async () => {
        const { t, authed } = await fixture()
        for (const name of [
            'addExpense',
            'addIncome',
            'updateTransaction',
            'deleteTransaction',
        ]) {
            const result = await execute(t, name, {
                id: 't0',
                recurrence: { frequency: 'monthly' },
                scope: 'all-future',
            })
            expect(result.ok, name).toBe(false)
        }
        expect(await authed.query(api.v1.sync.queries.getCounter, {})).toBe(7n)
        const skill = await execute(t, 'readSkill', {
            slug: 'recurring-movements',
        })
        expect(skill.ok).toBe(false)
        expect(skill.availableSlugs).not.toContain('recurring-movements')
    })

    it('excludes future occurrences from every WhatsApp activity filter and summaries', async () => {
        const { t } = await fixture()
        for (const filter of [
            {},
            { accountIdOrName: 'a' },
            { categoryIdOrName: 'c' },
            { type: 'expense' },
            { status: 'cleared' },
        ]) {
            const result = await execute(t, 'listTransactions', {
                ...filter,
                dateTo: '2026-09-30',
            })
            expect(result.ok).toBe(true)
            expect(result.items).toMatchObject([{ id: 't0' }])
            expect(result.items).toHaveLength(1)
        }
        const tagged = await execute(t, 'listTransactions', {
            tagIdOrName: 'tag',
        })
        expect(tagged.items).toEqual([])
        const summary = await execute(t, 'summarizeTransactions', {
            dateFrom: '2026-09-01',
            dateTo: '2026-09-30',
            groupBy: 'category',
        })
        expect(summary.rows).toMatchObject([{ total: 100 }])
        const futureOnly = await execute(t, 'summarizeTransactions', {
            dateFrom: '2026-09-14',
            dateTo: '2026-09-30',
            groupBy: 'category',
        })
        expect(futureOnly.rows).toEqual([])
    })

    it('uses the occurred balance for WhatsApp reads and balance adjustments', async () => {
        const { t } = await fixture()
        expect(
            await execute(t, 'getAccountBalance', { idOrName: 'a' }),
        ).toMatchObject({ ok: true, balance: -100 })
        expect(
            await execute(t, 'addBalanceAdjustment', {
                accountIdOrName: 'a',
                balanceAfter: 50,
                dateConfirmed: false,
                timeStatus: 'none',
            }),
        ).toMatchObject({ ok: true, previousBalance: -100, balanceAfter: 50 })
        expect(
            await execute(t, 'getAccountBalance', { idOrName: 'a' }),
        ).toMatchObject({ ok: true, balance: 50 })
    })
})
