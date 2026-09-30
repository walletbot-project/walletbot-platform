// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import aggregate from '@convex-dev/aggregate/test'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { api } from '../_generated/api'
import schema from '../schema'

const modules = import.meta.glob('../**/*.ts')
const now = Date.UTC(2026, 8, 30, 12, 0)
const legacy = { platform: 'android', appVersion: '0.4.0' }
const userId = 'ordering-user'
const otherUserId = 'ordering-other-user'

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
        for (const [index, id] of ['a1', 'a2', 'a3'].entries()) {
            await ctx.db.insert('accounts', {
                userId,
                id,
                name: `Account ${id}`,
                currency: 'ARS',
                color: '#000000',
                icon: 'wallet',
                isArchived: false,
                createdAt: BigInt(index + 1),
                updatedAt: BigInt(index + 1),
                seq: BigInt(index + 1),
            })
        }
        for (const [index, id] of ['c1', 'c2', 'c3'].entries()) {
            await ctx.db.insert('categories', {
                userId,
                id,
                // Reverse-alphabetical, so a name sort would be visible.
                name: `Category ${3 - index}`,
                color: '#000000',
                icon: 'category',
                isArchived: false,
                createdAt: BigInt(index + 1),
                updatedAt: BigInt(index + 1),
                seq: BigInt(index + 4),
            })
        }
        await ctx.db.insert('accounts', {
            userId: otherUserId,
            id: 'foreign',
            name: 'Not yours',
            currency: 'ARS',
            color: '#000000',
            icon: 'wallet',
            isArchived: false,
            createdAt: 1n,
            updatedAt: 1n,
            seq: 1n,
        })
        await ctx.db.insert('syncCounters', { userId, value: 6n })
    })
    return { t, authed }
}

async function activeAccountIds(
    authed: Awaited<ReturnType<typeof fixture>>['authed'],
) {
    return (await authed.query(api.v1.accounts.queries.listActive, {})).map(
        (a) => a.id,
    )
}

describe('account and category ordering', { timeout: 30000 }, () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(now)
        vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
    })
    afterEach(() => {
        vi.useRealTimers()
        vi.unstubAllEnvs()
    })

    it('lists in creation order until the user reorders', async () => {
        const { authed } = await fixture()
        expect(await activeAccountIds(authed)).toEqual(['a1', 'a2', 'a3'])
        expect(
            (
                await authed.query(
                    api.v1.categories.queries.listActiveWithCounts,
                    {},
                )
            ).map((c) => c.id),
        ).toEqual(['c1', 'c2', 'c3'])
    })

    it('persists a reorder and puts unpositioned rows last', async () => {
        const { t, authed } = await fixture()
        await authed.mutation(api.v1.accounts.mutations.reorder, {
            ids: ['a3', 'a1'],
        })
        // a2 was not part of the write, so it sorts after the positioned rows.
        expect(await activeAccountIds(authed)).toEqual(['a3', 'a1', 'a2'])

        await authed.mutation(api.v1.categories.mutations.reorder, {
            ids: ['c3', 'c2', 'c1'],
        })
        const categories = await authed.query(
            api.v1.categories.queries.listActive,
            {},
        )
        expect(categories.map((c) => [c.id, c.position])).toEqual([
            ['c3', 0],
            ['c2', 1],
            ['c1', 2],
        ])

        // Every moved row got a fresh seq, so other devices pull it.
        const rows = await t.run(async (ctx) =>
            ctx.db
                .query('categories')
                .withIndex('by_user_seq', (q) =>
                    q.eq('userId', userId).gt('seq', 6n),
                )
                .collect(),
        )
        expect(rows.map((r) => r.id).sort()).toEqual(['c1', 'c2', 'c3'])
    })

    it("never touches another user's rows", async () => {
        const { t, authed } = await fixture()
        await authed.mutation(api.v1.accounts.mutations.reorder, {
            ids: ['foreign', 'a2'],
        })
        const foreign = await t.run(async (ctx) =>
            ctx.db
                .query('accounts')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', otherUserId).eq('id', 'foreign'),
                )
                .unique(),
        )
        expect(foreign?.position).toBeUndefined()
        expect(await activeAccountIds(authed)).toEqual(['a2', 'a1', 'a3'])
    })

    it('rejects duplicate ids', async () => {
        const { authed } = await fixture()
        await expect(
            authed.mutation(api.v1.accounts.mutations.reorder, {
                ids: ['a1', 'a1'],
            }),
        ).rejects.toThrow()
    })

    it('keeps the order when a client without positions edits a row', async () => {
        const { authed } = await fixture()
        await authed.mutation(api.v1.accounts.mutations.reorder, {
            ids: ['a3', 'a2', 'a1'],
        })
        await authed.mutation(api.v1.categories.mutations.reorder, {
            ids: ['c2', 'c1', 'c3'],
        })
        const counter = await authed.query(api.v1.sync.queries.getCounter, {})

        // A 0.4.0 client renames a1 and c1: its upserts carry no `position`.
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...legacy,
            expectedServerSeq: counter,
            upserts: {
                accounts: [
                    {
                        id: 'a1',
                        name: 'Renamed',
                        currency: 'ARS',
                        color: '#000000',
                        icon: 'wallet',
                        isArchived: false,
                        createdAt: 1n,
                        updatedAt: 100n,
                    },
                ],
                categories: [
                    {
                        id: 'c1',
                        name: 'Renamed',
                        color: '#000000',
                        icon: 'category',
                        isArchived: false,
                        createdAt: 1n,
                        updatedAt: 100n,
                    },
                ],
            },
        })
        expect(result.ok).toBe(true)
        expect(await activeAccountIds(authed)).toEqual(['a3', 'a2', 'a1'])
        expect(
            (await authed.query(api.v1.categories.queries.listActive, {})).map(
                (c) => c.id,
            ),
        ).toEqual(['c2', 'c1', 'c3'])
    })

    it('stores the position a current client pushes', async () => {
        const { authed } = await fixture()
        const counter = await authed.query(api.v1.sync.queries.getCounter, {})
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...legacy,
            expectedServerSeq: counter,
            upserts: {
                accounts: [
                    {
                        id: 'a3',
                        name: 'Account a3',
                        currency: 'ARS',
                        color: '#000000',
                        icon: 'wallet',
                        position: 0,
                        isArchived: false,
                        createdAt: 3n,
                        updatedAt: 100n,
                    },
                ],
            },
        })
        expect(result.ok).toBe(true)
        expect((await activeAccountIds(authed))[0]).toBe('a3')
    })
})
