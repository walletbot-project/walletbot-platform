// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import aggregate from '@convex-dev/aggregate/test'
import migrationsTest from '@convex-dev/migrations/test'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { api, internal } from '../_generated/api'
import { isClientSupported } from '../config/helpers'
import schema from '../schema'
import { aggregateInsert } from '../transactions/helpers'

const modules = import.meta.glob('../**/*.ts')
const now = Date.UTC(2026, 8, 13, 12, 0)
const legacy = { platform: 'android', appVersion: '0.3.2' }
const modern = { platform: 'android', appVersion: '0.4.0' }
const userId = 'compatibility-user'

async function fixture() {
    const t = convexTest(schema, modules)
    aggregate.register(t, 'outflowsByAccount')
    aggregate.register(t, 'inflowsByAccount')
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

    it('keeps the previous supported floor on every native platform', () => {
        for (const platform of ['android', 'ios', 'macos']) {
            expect(isClientSupported(platform, '0.3.0')).toBe(true)
            expect(isClientSupported(platform, '0.3.2')).toBe(true)
            expect(isClientSupported(platform, '0.2.0')).toBe(false)
        }
    })

    it('projects future rows away without changing canonical data', async () => {
        const { authed } = await fixture()
        const old = await authed.query(api.v1.sync.queries.pull, {
            ...legacy,
            since: 0n,
        })
        if ('error' in old) throw new Error(old.error)
        expect(
            old.rows
                .filter((r) => r.tableName === 'transactions')
                .map((r) => r.row.id),
        ).toEqual(['t0'])
        expect(old.rows.some((r) => r.tableName === 'recurrences')).toBe(false)
        expect(old.rows.some((r) => r.tableName === 'transactionTags')).toBe(
            false,
        )
        expect(old.tombstones.map((t) => t.entityId).sort()).toEqual([
            't1',
            't1__tag',
        ])
        expect(
            old.rows.find((r) => r.tableName === 'transactions')?.row,
        ).not.toHaveProperty('recurrenceId')
        const current = await authed.query(api.v1.sync.queries.pull, {
            ...modern,
            since: 0n,
        })
        if ('error' in current) throw new Error(current.error)
        expect(
            current.rows.filter((r) => r.tableName === 'transactions'),
        ).toHaveLength(2)
        expect(current.rows.some((r) => r.tableName === 'recurrences')).toBe(
            true,
        )
        expect(current.rows.every((r) => !('legacyPendingDate' in r.row))).toBe(
            true,
        )
    })

    it('advances through pages containing only hidden data', async () => {
        const { authed } = await fixture()
        let since = 0n
        const seen: string[] = []
        for (let pageNumber = 0; pageNumber < 20; pageNumber++) {
            const page = await authed.query(api.v1.sync.queries.pull, {
                ...legacy,
                since,
                limit: 1,
            })
            if ('error' in page) throw new Error(page.error)
            seen.push(...page.rows.map((r) => String(r.row.id)))
            if (!page.hasMore) {
                expect(page.currentCounter).toBe(7n)
                break
            }
            expect(page.nextCursor).toBeGreaterThan(since)
            since = page.nextCursor ?? since
        }
        expect(seen).toEqual(['a', 'c', 't0', 'tag'])
    })

    it('publishes due occurrences and tags after the old cursor, preserving edit timestamps', async () => {
        const { t, authed } = await fixture()
        vi.setSystemTime(now + 3600000)
        await t.mutation(internal.occurrences.internal.publishDue, {})
        const page = await authed.query(api.v1.sync.queries.pull, {
            ...legacy,
            since: 7n,
        })
        if ('error' in page) throw new Error(page.error)
        expect(page.rows.map((r) => r.row.id)).toEqual(['t1', 't1__tag'])
        expect(page.rows[0].row.updatedAt).toBe(10n)
        expect(page.rows[1].row.updatedAt).toBe(2n)
        await t.mutation(internal.occurrences.internal.publishDue, {})
        expect(await authed.query(api.v1.sync.queries.getCounter, {})).toBe(
            page.currentCounter,
        )
    })

    it('preserves series metadata on legacy edit and delete, without requiring new fields', async () => {
        const { authed } = await fixture()
        const transaction = {
            id: 't0',
            type: 'expense' as const,
            name: 'Edited offline',
            status: 'cleared' as const,
            date: BigInt(now - 1000),
            accountId: 'a',
            categoryId: 'c',
            currency: 'ARS',
            amount: 12000n,
            isArchived: false,
            createdAt: 1n,
            updatedAt: 20n,
        }
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...legacy,
            expectedServerSeq: 7n,
            upserts: { transactions: [transaction] },
        })
        expect(result.ok).toBe(true)
        const row = await authed.query(api.v1.transactions.queries.get, {
            id: 't0',
        })
        expect(row).toMatchObject({
            name: 'Edited offline',
            amount: 12000n,
            recurrenceId: 'r',
            recurrenceIndex: 0n,
        })
        const counter = await authed.query(api.v1.sync.queries.getCounter, {})
        await authed.mutation(api.v1.sync.mutations.push, {
            ...legacy,
            expectedServerSeq: counter,
            upserts: {
                transactions: [
                    { ...transaction, isArchived: true, updatedAt: 30n },
                ],
            },
            tombstones: [
                { tableName: 'transactions', entityId: 't0', deletedAt: 30n },
            ],
        })
        expect(
            await authed.query(api.v1.transactions.queries.get, { id: 't0' }),
        ).toMatchObject({ isArchived: true, recurrenceId: 'r' })
        expect(
            await authed.query(api.v1.transactions.queries.get, { id: 't1' }),
        ).toMatchObject({ isArchived: false })
        const page = await authed.query(api.v1.sync.queries.pull, {
            ...modern,
            since: counter,
        })
        if ('error' in page) throw new Error(page.error)
        expect(page.rows.find((r) => r.row.id === 't0')?.row.isArchived).toBe(
            true,
        )
        expect(page.tombstones.some((t) => t.entityId === 't0')).toBe(false)
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

    it('rehydrates tags when an occurrence is moved from future to past', async () => {
        const { authed } = await fixture()
        await authed.mutation(api.v1.transactions.mutations.update, {
            id: 't1',
            date: BigInt(now - 100),
        })
        const page = await authed.query(api.v1.sync.queries.pull, {
            ...legacy,
            since: 7n,
        })
        if ('error' in page) throw new Error(page.error)
        expect(page.rows.map((r) => r.row.id)).toEqual(['t1', 't1__tag'])
    })
    it('reprojects a legacy future write after its own push acknowledgement', async () => {
        const { t, authed } = await fixture()
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...legacy,
            expectedServerSeq: 7n,
            upserts: {
                transactions: [
                    {
                        id: 't0',
                        type: 'expense',
                        name: 'Moved offline',
                        status: 'cleared',
                        date: BigInt(now + 7200000),
                        accountId: 'a',
                        categoryId: 'c',
                        currency: 'ARS',
                        amount: 10000n,
                        isArchived: false,
                        createdAt: 1n,
                        updatedAt: 20n,
                    },
                ],
            },
        })
        if (!result.ok) throw new Error(result.error)
        await t.finishAllScheduledFunctions(() => vi.runAllTimers())
        const page = await authed.query(api.v1.sync.queries.pull, {
            ...legacy,
            since: result.newSeq,
        })
        if ('error' in page) throw new Error(page.error)
        expect(page.tombstones.map((x) => x.entityId)).toContain('t0')
        expect(
            page.rows.filter((x) => x.tableName === 'transactions'),
        ).toHaveLength(0)
    })

    it('does not publish a rescheduled or archived occurrence at its previous due date', async () => {
        const { t, authed } = await fixture()
        await authed.mutation(api.v1.transactions.mutations.update, {
            id: 't1',
            date: BigInt(now + 7200000),
        })
        const cursor = await authed.query(api.v1.sync.queries.getCounter, {})
        vi.setSystemTime(now + 3600000)
        await t.mutation(internal.occurrences.internal.publishDue, {})
        expect(await authed.query(api.v1.sync.queries.getCounter, {})).toBe(
            cursor,
        )
        await authed.mutation(api.v1.transactions.mutations.archive, {
            id: 't1',
        })
        const afterDelete = await authed.query(
            api.v1.sync.queries.getCounter,
            {},
        )
        vi.setSystemTime(now + 7200000)
        await t.mutation(internal.occurrences.internal.publishDue, {})
        expect(await authed.query(api.v1.sync.queries.getCounter, {})).toBe(
            afterDelete,
        )
    })

    it('queues pre-deploy future rows and updates the legacy web clock idempotently', async () => {
        const { t, authed } = await fixture()
        migrationsTest.register(t)
        await t.run(async (ctx) => {
            const row = await ctx.db
                .query('transactions')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', 't1'),
                )
                .unique()
            if (!row) throw new Error('missing fixture')
            await ctx.db.patch(row._id, { legacyPendingDate: undefined })
        })
        await t.mutation(internal.occurrences.internal.tick, {})
        await t.finishAllScheduledFunctions(() => vi.runAllTimers())
        const cursor = await authed.query(api.v1.sync.queries.getCounter, {})
        expect(cursor).toBeGreaterThan(7n)
        await t.mutation(internal.occurrences.internal.tick, {})
        await t.finishAllScheduledFunctions(() => vi.runAllTimers())
        expect(await authed.query(api.v1.sync.queries.getCounter, {})).toBe(
            cursor,
        )
        vi.setSystemTime(now + 3600000)
        await t.mutation(internal.occurrences.internal.tick, {})
        await t.finishAllScheduledFunctions(() => vi.runAllTimers())
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

    it('publishes a future WhatsApp write and its tags to an already-synced legacy device when due', async () => {
        const { t, authed } = await fixture()
        const result = await execute(t, 'addExpense', {
            amount: 12,
            dateConfirmed: true,
            timeStatus: 'none',
            accountIdOrName: 'a',
            categoryIdOrName: 'c',
            name: 'Future WhatsApp',
            date: '2026-09-14',
            tagIdsOrNames: ['tag'],
        })
        expect(result.ok).toBe(true)
        const id = result.id
        if (typeof id !== 'string') throw new Error('missing movement id')
        const row = await t.run((ctx) =>
            ctx.db
                .query('transactions')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', id),
                )
                .unique(),
        )
        expect(row?.legacyPendingDate).toBe(row?.date)
        const before = await authed.query(api.v1.sync.queries.pull, {
            ...legacy,
            since: 0n,
        })
        if ('error' in before) throw new Error(before.error)
        expect(before.tombstones.some((r) => r.entityId === id)).toBe(true)
        vi.setSystemTime(now + 3 * 86400000)
        await t.mutation(internal.occurrences.internal.publishDue, {})
        const after = await authed.query(api.v1.sync.queries.pull, {
            ...legacy,
            since: before.currentCounter,
        })
        if ('error' in after) throw new Error(after.error)
        expect(
            after.rows.some(
                (r) => r.tableName === 'transactions' && r.row.id === id,
            ),
        ).toBe(true)
        expect(
            after.rows.some(
                (r) =>
                    r.tableName === 'transactionTags' &&
                    r.row.transactionId === id,
            ),
        ).toBe(true)
    })

    it('republishes hidden tags when WhatsApp moves an occurrence into the past', async () => {
        const { t, authed } = await fixture()
        const result = await execute(t, 'updateTransaction', {
            id: 't1',
            date: '2026-09-12',
            timeStatus: 'none',
        })
        expect(result.ok).toBe(true)
        const page = await authed.query(api.v1.sync.queries.pull, {
            ...legacy,
            since: 7n,
        })
        if ('error' in page) throw new Error(page.error)
        expect(
            page.rows.some(
                (r) =>
                    r.tableName === 'transactionTags' && r.row.id === 't1__tag',
            ),
        ).toBe(true)
        expect(
            page.rows.some(
                (r) => r.tableName === 'transactions' && r.row.id === 't1',
            ),
        ).toBe(true)
    })

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
