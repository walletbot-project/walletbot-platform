// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import aggregate from '@convex-dev/aggregate/test'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { api } from '../_generated/api'
import schema from '../schema'

const modules = import.meta.glob('../**/*.ts')
const now = Date.UTC(2026, 9, 3, 12, 0)
const client = { platform: 'android', appVersion: '0.4.0' }
const userId = 'push-telemetry-user'

async function fixture() {
    const t = convexTest(schema, modules)
    aggregate.register(t, 'outflowsByAccount')
    aggregate.register(t, 'inflowsByAccount')
    aggregate.register(t, 'transactionsByTag')
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
            name: 'Food',
            color: '#000000',
            icon: 'food',
            isArchived: false,
            createdAt: 1n,
            updatedAt: 1n,
            seq: 2n,
        })
        await ctx.db.insert('syncCounters', { userId, value: 2n })
    })
    return { t, authed }
}

const category = {
    id: 'c2',
    name: 'Rent',
    color: '#000000',
    icon: 'home',
    isArchived: false,
    createdAt: 10n,
    updatedAt: 10n,
}

const transaction = (currency: string) => ({
    id: 't',
    type: 'expense' as const,
    name: 'Lunch',
    status: 'cleared' as const,
    date: BigInt(now),
    accountId: 'a',
    categoryId: 'c',
    currency,
    amount: 1000n,
    isArchived: false,
    createdAt: 10n,
    updatedAt: 10n,
})

async function backendMetrics(t: Awaited<ReturnType<typeof fixture>>['t']) {
    return await t.run(async (ctx) =>
        (await ctx.db.query('telemetryMetrics').take(20)).map((m) => ({
            name: m.name,
            attributes: m.attributes,
        })),
    )
}

describe('push telemetry', { timeout: 30000 }, () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(now)
        vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
    })
    afterEach(() => {
        vi.useRealTimers()
        vi.unstubAllEnvs()
    })

    it('records one ok duration sample for an applied batch', async () => {
        const { t, authed } = await fixture()
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 2n,
            upserts: { transactions: [transaction('ARS')] },
        })
        expect(result).toEqual({ ok: true, newSeq: 3n })
        expect(await backendMetrics(t)).toEqual([
            {
                name: 'system.function.duration_bucket_count',
                attributes: expect.objectContaining({
                    function: 'sync_push',
                    status: 'ok',
                }),
            },
        ])
    })

    it('rolls back a failed batch but commits its error telemetry', async () => {
        const { t, authed } = await fixture()
        // The category is applied before the transaction fails validation,
        // so it proves the whole batch rolled back, not just the bad row.
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 2n,
            upserts: {
                categories: [category],
                transactions: [transaction('USD')],
            },
        })
        expect(result).toEqual({
            ok: false,
            error: 'push_failed',
            reason: 'validation',
        })
        expect(await authed.query(api.v1.sync.queries.getCounter, {})).toBe(2n)
        await t.run(async (ctx) => {
            const written = await ctx.db
                .query('categories')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', 'c2'),
                )
                .unique()
            expect(written).toBeNull()
        })
        expect(await backendMetrics(t)).toEqual([
            {
                name: 'sync.errors.count',
                attributes: {
                    direction: 'push',
                    reason: 'validation',
                    platform: 'android',
                },
            },
            {
                name: 'system.function.duration_bucket_count',
                attributes: expect.objectContaining({
                    function: 'sync_push',
                    status: 'error',
                }),
            },
        ])
    })

    it('records a cursor mismatch as a rejection, not an error', async () => {
        const { t, authed } = await fixture()
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 1n,
            upserts: { categories: [category] },
        })
        expect(result).toEqual({
            ok: false,
            error: 'cursor_mismatch',
            currentCounter: 2n,
        })
        expect(await backendMetrics(t)).toEqual([
            {
                name: 'sync.errors.count',
                attributes: {
                    direction: 'push',
                    reason: 'cursor_mismatch',
                    platform: 'android',
                },
            },
            {
                name: 'system.function.duration_bucket_count',
                attributes: expect.objectContaining({
                    function: 'sync_push',
                    status: 'rejected',
                }),
            },
        ])
    })

    it('records an outdated client as a rejection', async () => {
        const { t, authed } = await fixture()
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            platform: 'android',
            appVersion: '0.2.0',
            expectedServerSeq: 2n,
            upserts: { categories: [category] },
        })
        expect(result).toMatchObject({ ok: false })
        expect(await backendMetrics(t)).toEqual([
            {
                name: 'sync.errors.count',
                attributes: {
                    direction: 'push',
                    reason: 'client_outdated',
                    platform: 'android',
                },
            },
            {
                name: 'system.function.duration_bucket_count',
                attributes: expect.objectContaining({
                    function: 'sync_push',
                    status: 'rejected',
                }),
            },
        ])
    })
})
