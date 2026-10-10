// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import aggregate from '@convex-dev/aggregate/test'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { api } from '../_generated/api'
import schema from '../schema'

// Sync correctness and recovery from the backend's side: whatever the client
// retries after a rejection, a failed batch or a lost ack, the server state
// converges to the batch applied exactly once.

const modules = import.meta.glob('../**/*.ts')
const now = Date.UTC(2026, 9, 3, 12, 0)
const client = { platform: 'android', appVersion: '0.6.0' }
const userId = 'convergence-user'

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

const category = (id: string, name: string) => ({
    id,
    name,
    color: '#000000',
    icon: 'home',
    isArchived: false,
    createdAt: 10n,
    updatedAt: 10n,
})

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

type Fixture = Awaited<ReturnType<typeof fixture>>

const counter = (authed: Fixture['authed']) =>
    authed.query(api.v1.sync.queries.getCounter, {})

async function rows(t: Fixture['t']) {
    return await t.run(async (ctx) => ({
        categories: (
            await ctx.db
                .query('categories')
                .withIndex('by_user_id', (q) => q.eq('userId', userId))
                .take(20)
        ).map((c) => c.id),
        transactions: (
            await ctx.db
                .query('transactions')
                .withIndex('by_user_id', (q) => q.eq('userId', userId))
                .take(20)
        ).map((tx) => tx.id),
    }))
}

describe('sync convergence', { timeout: 30000 }, () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(now)
        vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
    })
    afterEach(() => {
        vi.useRealTimers()
        vi.unstubAllEnvs()
    })

    it('applies a batch once the client drains pull after a cursor mismatch', async () => {
        const { t, authed } = await fixture()
        const batch = { upserts: { categories: [category('c2', 'Rent')] } }

        // Another device wrote first: the client's cursor is stale.
        const rejected = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            ...batch,
            expectedServerSeq: 1n,
        })
        expect(rejected).toEqual({
            ok: false,
            error: 'cursor_mismatch',
            currentCounter: 2n,
        })
        expect(await counter(authed)).toBe(2n)

        // Drain pull from the stale cursor, then retry at the reported head.
        const page = await authed.query(api.v1.sync.queries.pull, {
            ...client,
            since: 1n,
        })
        expect(page).toMatchObject({ currentCounter: 2n, hasMore: false })
        const retried = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            ...batch,
            expectedServerSeq: 2n,
        })
        expect(retried).toEqual({ ok: true, newSeq: 3n })
        expect((await rows(t)).categories.sort()).toEqual(['c', 'c2'])
    })

    it('converges without duplicates when an applied batch is retried after a lost ack', async () => {
        const { t, authed } = await fixture()
        const batch = {
            upserts: {
                categories: [category('c2', 'Rent')],
                transactions: [transaction('ARS')],
            },
        }
        const applied = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            ...batch,
            expectedServerSeq: 2n,
        })
        expect(applied).toEqual({ ok: true, newSeq: 3n })

        // The ack never reached the client, which retries the same batch at
        // its old cursor, is told to drain, sees its own rows, and retries.
        const stale = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            ...batch,
            expectedServerSeq: 2n,
        })
        expect(stale).toMatchObject({ ok: false, error: 'cursor_mismatch' })
        const page = await authed.query(api.v1.sync.queries.pull, {
            ...client,
            since: 2n,
        })
        expect(page).toMatchObject({ currentCounter: 3n })
        const again = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            ...batch,
            expectedServerSeq: 3n,
        })
        expect(again).toEqual({ ok: true, newSeq: 4n })

        expect(await rows(t)).toEqual({
            categories: expect.arrayContaining(['c', 'c2']),
            transactions: ['t'],
        })
        expect((await rows(t)).categories).toHaveLength(2)
    })

    it('resolves a row it cannot store instead of failing the batch', async () => {
        const { t, authed } = await fixture()
        const batch = {
            upserts: {
                categories: [category('c2', 'Rent')],
                transactions: [transaction('USD')],
            },
        }
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            ...batch,
            expectedServerSeq: 2n,
        })
        expect(result).toEqual({ ok: true, newSeq: 3n })
        // The good row landed; the USD movement on an ARS account was dropped
        // at a later seq, so the device that sent it pulls the tombstone.
        expect(await rows(t)).toEqual({
            categories: expect.arrayContaining(['c', 'c2']),
            transactions: [],
        })
        expect(await counter(authed)).toBe(4n)
        const page = await authed.query(api.v1.sync.queries.pull, {
            ...client,
            since: 3n,
        })
        expect(page).toMatchObject({
            rows: [],
            tombstones: [{ tableName: 'transactions', entityId: 't', seq: 4n }],
            currentCounter: 4n,
        })

        // The device keeps sending it until it pulls: same outcome each time.
        const again = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            ...batch,
            expectedServerSeq: 4n,
        })
        expect(again).toEqual({ ok: true, newSeq: 5n })
        expect((await rows(t)).transactions).toEqual([])
    })

    it('fails a batch that hits a bug the same way every retry, then applies it at the same cursor once fixed', async () => {
        const { t, authed } = await fixture()
        // A second row under account `a`'s id is corrupt data: every lookup
        // of `a` throws, standing in for a bug.
        const duplicate = await t.run(
            async (ctx) =>
                await ctx.db.insert('accounts', {
                    userId,
                    id: 'a',
                    name: 'Cash copy',
                    currency: 'ARS',
                    color: '#000000',
                    icon: 'wallet',
                    isArchived: false,
                    createdAt: 1n,
                    updatedAt: 1n,
                    seq: 1n,
                }),
        )
        const batch = {
            upserts: {
                categories: [category('c2', 'Rent')],
                transactions: [transaction('ARS')],
            },
        }
        for (let attempt = 0; attempt < 3; attempt++) {
            const result = await authed.mutation(api.v1.sync.mutations.push, {
                ...client,
                ...batch,
                expectedServerSeq: 2n,
            })
            expect(result).toEqual({
                ok: false,
                error: 'push_failed',
                reason: 'unknown',
            })
        }
        expect(await counter(authed)).toBe(2n)
        expect(await rows(t)).toEqual({ categories: ['c'], transactions: [] })

        // The failed batches never bumped the counter, so the client's cursor
        // is still current and the same batch applies straight away.
        await t.run(async (ctx) => await ctx.db.delete(duplicate))
        const fixed = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            ...batch,
            expectedServerSeq: 2n,
        })
        expect(fixed).toEqual({ ok: true, newSeq: 3n })
        expect(await rows(t)).toEqual({
            categories: expect.arrayContaining(['c', 'c2']),
            transactions: ['t'],
        })
    })
})
