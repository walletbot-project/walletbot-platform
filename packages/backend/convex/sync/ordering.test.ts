// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import aggregate from '@convex-dev/aggregate/test'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { api, internal } from '../_generated/api'
import schema from '../schema'

const modules = import.meta.glob('../**/*.ts')
const now = Date.UTC(2026, 8, 30, 12, 0)
const client = { platform: 'android', appVersion: '0.6.0' }
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

        // A client renames a1 and c1 without a `position` in its upserts.
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
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
            ...client,
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

describe('tag ordering', { timeout: 30000 }, () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(now)
        vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
    })
    afterEach(() => {
        vi.useRealTimers()
        vi.unstubAllEnvs()
    })

    // A (children B, D), C top-level, E top-level. Names chosen so the
    // alphabetical fallback is visible.
    async function tagFixture() {
        const { t, authed } = await fixture()
        await t.run(async (ctx) => {
            const tags: [string, string, string | undefined][] = [
                ['A', 'Hogar', undefined],
                ['B', 'Luz', 'A'],
                ['D', 'Agua', 'A'],
                ['C', 'Auto', undefined],
                ['E', 'Viajes', undefined],
            ]
            for (const [index, [id, name, parentId]] of tags.entries()) {
                await ctx.db.insert('tags', {
                    userId,
                    id,
                    name,
                    parentId,
                    color: '#000000',
                    isArchived: false,
                    createdAt: BigInt(index + 1),
                    updatedAt: BigInt(index + 1),
                    seq: BigInt(index + 7),
                })
            }
            const counter = await ctx.db
                .query('syncCounters')
                .withIndex('by_user', (q) => q.eq('userId', userId))
                .unique()
            if (counter) await ctx.db.patch(counter._id, { value: 11n })
        })
        return { t, authed }
    }

    async function tagOrder(
        authed: Awaited<ReturnType<typeof fixture>>['authed'],
    ) {
        return (
            await authed.query(api.v1.tags.queries.listActiveWithCounts, {})
        ).map((tag) => tag.id)
    }

    it('lists alphabetically until a level is reordered', async () => {
        const { authed } = await tagFixture()
        // Agua, Auto, Hogar, Luz, Viajes
        expect(await tagOrder(authed)).toEqual(['D', 'C', 'A', 'B', 'E'])
    })

    it('reorders one level, leaving unpositioned tags alphabetical after', async () => {
        const { authed } = await tagFixture()
        await authed.mutation(api.v1.tags.mutations.reorder, {
            ids: ['E', 'A'],
        })
        await authed.mutation(api.v1.tags.mutations.reorder, {
            parentId: 'A',
            ids: ['B', 'D'],
        })
        const rows = await authed.query(
            api.v1.tags.queries.listActiveWithCounts,
            {},
        )
        const roots = rows.filter((r) => r.parentId === undefined)
        const underA = rows.filter((r) => r.parentId === 'A')
        expect(roots.map((r) => r.id)).toEqual(['E', 'A', 'C'])
        expect(underA.map((r) => r.id)).toEqual(['B', 'D'])
    })

    it('never moves a tag across levels', async () => {
        const { t, authed } = await tagFixture()
        await expect(
            authed.mutation(api.v1.tags.mutations.reorder, {
                ids: ['B', 'A'],
            }),
        ).rejects.toThrow('Tags can only be reordered among siblings')
        await expect(
            authed.mutation(api.v1.tags.mutations.reorder, {
                parentId: 'A',
                ids: ['C', 'B'],
            }),
        ).rejects.toThrow('Tags can only be reordered among siblings')
        // Nothing was half-written.
        const anyPositioned = await t.run(async (ctx) =>
            (
                await ctx.db
                    .query('tags')
                    .withIndex('by_user_archived', (q) =>
                        q.eq('userId', userId).eq('isArchived', false),
                    )
                    .collect()
            ).some((r) => r.position !== undefined),
        )
        expect(anyPositioned).toBe(false)
    })

    it('drops the position when a tag changes parent', async () => {
        const { t, authed } = await tagFixture()
        await authed.mutation(api.v1.tags.mutations.reorder, {
            ids: ['E', 'C', 'A'],
        })
        await authed.mutation(api.v1.tags.mutations.update, {
            id: 'C',
            parentId: 'A',
        })
        // Renaming keeps it.
        await authed.mutation(api.v1.tags.mutations.update, {
            id: 'E',
            name: 'Vacaciones',
        })
        const byId = await t.run(async (ctx) => {
            const rows = await ctx.db
                .query('tags')
                .withIndex('by_user_archived', (q) =>
                    q.eq('userId', userId).eq('isArchived', false),
                )
                .collect()
            return Object.fromEntries(rows.map((r) => [r.id, r]))
        })
        expect('position' in byId.C).toBe(false)
        expect(byId.E.position).toBe(0)
    })

    it('the agent drops the position when it moves a tag, keeps it on rename', async () => {
        const { t, authed } = await tagFixture()
        await authed.mutation(api.v1.tags.mutations.reorder, {
            ids: ['E', 'C', 'A'],
        })
        const run = (argsJson: object) =>
            t.mutation(internal.agent.tools.execute, {
                userId,
                name: 'updateTag',
                argsJson: JSON.stringify(argsJson),
                nowMs: now,
                utcOffsetMinutes: 0,
            })
        await run({ idOrName: 'C', parentIdOrName: 'A' })
        await run({ idOrName: 'E', name: 'Vacaciones' })
        const byId = await t.run(async (ctx) => {
            const rows = await ctx.db
                .query('tags')
                .withIndex('by_user_archived', (q) =>
                    q.eq('userId', userId).eq('isArchived', false),
                )
                .collect()
            return Object.fromEntries(rows.map((r) => [r.id, r]))
        })
        expect(byId.C.parentId).toBe('A')
        expect('position' in byId.C).toBe(false)
        expect(byId.E.name).toBe('Vacaciones')
        expect(byId.E.position).toBe(0)
    })

    it('re-parented children of an archived tag lose their position', async () => {
        const { t, authed } = await tagFixture()
        await authed.mutation(api.v1.tags.mutations.reorder, {
            parentId: 'A',
            ids: ['B', 'D'],
        })
        await authed.mutation(api.v1.tags.mutations.archive, { id: 'A' })
        const rows = await t.run(async (ctx) =>
            ctx.db
                .query('tags')
                .withIndex('by_user_archived', (q) =>
                    q.eq('userId', userId).eq('isArchived', false),
                )
                .collect(),
        )
        const moved = rows.filter((r) => r.id === 'B' || r.id === 'D')
        expect(moved.map((r) => [r.parentId, 'position' in r])).toEqual([
            [undefined, false],
            [undefined, false],
        ])
    })

    it('sync keeps the position when a client omits it, but not across parents', async () => {
        const { authed } = await tagFixture()
        await authed.mutation(api.v1.tags.mutations.reorder, {
            ids: ['E', 'C', 'A'],
        })
        const counter = await authed.query(api.v1.sync.queries.getCounter, {})
        const base = {
            color: '#000000',
            isArchived: false,
            updatedAt: 100n,
        }
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: counter,
            upserts: {
                tags: [
                    // Renamed in place: keeps position 0.
                    { ...base, id: 'E', name: 'Vacaciones', createdAt: 5n },
                    // Moved under A: its root position no longer applies.
                    {
                        ...base,
                        id: 'C',
                        name: 'Auto',
                        parentId: 'A',
                        createdAt: 4n,
                    },
                ],
            },
        })
        expect(result.ok).toBe(true)
        const rows = await authed.query(
            api.v1.tags.queries.listActiveWithCounts,
            {},
        )
        const byId = Object.fromEntries(rows.map((r) => [r.id, r]))
        expect(byId.E.position).toBe(0)
        expect(byId.C.position).toBeUndefined()
    })
})
