// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import aggregate from '@convex-dev/aggregate/test'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { api } from '../_generated/api'
import schema from '../schema'

// Rows a device sends that the server can't store as sent. None of them may
// fail the batch: a failed batch is retried with the same rows forever and
// blocks every later change on that device.

const modules = import.meta.glob('../**/*.ts')
const now = Date.UTC(2026, 9, 10, 12, 0)
const client = { platform: 'android', appVersion: '0.6.0' }
const userId = 'conflicts-user'

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

type Fixture = Awaited<ReturnType<typeof fixture>>

async function deletedOnAnotherDevice(
    t: Fixture['t'],
    tableName: 'accounts' | 'categories' | 'tags' | 'transactions',
    entityId: string,
    mergedIntoId?: string,
) {
    await t.run(async (ctx) => {
        await ctx.db.insert('tombstones', {
            userId,
            tableName,
            entityId,
            seq: 2n,
            deletedAt: 5n,
            mergedIntoId,
        })
    })
}

const transaction = (
    overrides: Partial<{
        id: string
        name: string
        accountId: string
        categoryId: string
        currency: string
        isArchived: boolean
        updatedAt: bigint
    }> = {},
) => ({
    id: 't',
    type: 'expense' as const,
    name: 'Lunch',
    status: 'cleared' as const,
    date: BigInt(now),
    accountId: 'a',
    categoryId: 'c',
    currency: 'ARS',
    amount: 1000n,
    isArchived: false,
    createdAt: 10n,
    updatedAt: 10n,
    ...overrides,
})

const tag = (id: string, parentId?: string) => ({
    id,
    name: id,
    parentId,
    color: '#000000',
    isArchived: false,
    createdAt: 10n,
    updatedAt: 10n,
})

async function storedTransaction(t: Fixture['t'], id = 't') {
    return await t.run(
        async (ctx) =>
            await ctx.db
                .query('transactions')
                .withIndex('by_user_id', (q) =>
                    q.eq('userId', userId).eq('id', id),
                )
                .unique(),
    )
}

async function storedConflicts(t: Fixture['t']) {
    return await t.run(async (ctx) =>
        (
            await ctx.db
                .query('syncConflicts')
                .withIndex('by_user_table_entity', (q) =>
                    q.eq('userId', userId),
                )
                .take(20)
        ).map(({ tableName, entityId, reason, resolution, count }) => ({
            tableName,
            entityId,
            reason,
            resolution,
            count,
        })),
    )
}

async function pullSince(authed: Fixture['authed'], since: bigint) {
    return await authed.query(api.v1.sync.queries.pull, { ...client, since })
}

describe('sync push conflicts', { timeout: 30000 }, () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(now)
        vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
    })
    afterEach(() => {
        vi.useRealTimers()
        vi.unstubAllEnvs()
    })

    it('lets a device delete a movement whose account was deleted', async () => {
        const { t, authed } = await fixture()
        const account = {
            id: 'gone',
            name: 'Savings',
            currency: 'ARS',
            color: '#000000',
            icon: 'bank',
            isArchived: false,
            createdAt: 10n,
            updatedAt: 10n,
        }
        const adjustment = (isArchived: boolean, updatedAt: bigint) => ({
            ...transaction({
                id: 'orphan',
                name: 'Balance inicial',
                accountId: 'gone',
                categoryId: '',
                isArchived,
                updatedAt,
            }),
            type: 'balance_adjustment' as const,
            balanceAfter: 1000n,
        })
        // What happened in production: an account created with its opening
        // balance, then deleted. The delete removes the account and leaves
        // the adjustment behind.
        await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 2n,
            upserts: {
                accounts: [account],
                transactions: [adjustment(false, 10n)],
            },
        })
        await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 3n,
            upserts: {
                accounts: [{ ...account, isArchived: true, updatedAt: 15n }],
            },
            tombstones: [
                { tableName: 'accounts', entityId: 'gone', deletedAt: 15n },
            ],
        })
        expect(await storedTransaction(t, 'orphan')).not.toBeNull()

        // Deleting that leftover used to fail validation on every retry.
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 4n,
            upserts: { transactions: [adjustment(true, 20n)] },
            tombstones: [
                {
                    tableName: 'transactions',
                    entityId: 'orphan',
                    deletedAt: 20n,
                },
            ],
        })

        expect(result).toEqual({ ok: true, newSeq: 5n })
        expect(await storedTransaction(t, 'orphan')).toBeNull()
        expect(await storedConflicts(t)).toEqual([])
    })

    it('keeps edits and new movements on an account or category deleted elsewhere', async () => {
        const { t, authed } = await fixture()
        await deletedOnAnotherDevice(t, 'accounts', 'gone')
        await deletedOnAnotherDevice(t, 'categories', 'gone-category')

        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 2n,
            upserts: {
                transactions: [
                    transaction({
                        accountId: 'gone',
                        categoryId: 'gone-category',
                    }),
                ],
            },
        })

        expect(result).toEqual({ ok: true, newSeq: 3n })
        expect(await storedTransaction(t)).toMatchObject({
            accountId: 'gone',
            categoryId: 'gone-category',
            seq: 3n,
        })
        expect(await storedConflicts(t)).toEqual([])
    })

    it('drops a new movement on an account the user never had', async () => {
        const { t, authed } = await fixture()

        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 2n,
            upserts: { transactions: [transaction({ accountId: 'unknown' })] },
        })

        expect(result).toEqual({ ok: true, newSeq: 3n })
        expect(await storedTransaction(t)).toBeNull()
        expect(await pullSince(authed, 3n)).toMatchObject({
            tombstones: [{ tableName: 'transactions', entityId: 't', seq: 4n }],
        })
        expect(await storedConflicts(t)).toEqual([
            {
                tableName: 'transactions',
                entityId: 't',
                reason: 'transaction_account_missing',
                resolution: 'dropped',
                count: 1,
            },
        ])
    })

    it('sends the server copy back over an edit it cannot store', async () => {
        const { t, authed } = await fixture()
        await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 2n,
            upserts: { transactions: [transaction()] },
        })

        // A USD amount on an ARS account.
        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 3n,
            upserts: {
                transactions: [
                    transaction({
                        name: 'Dinner',
                        currency: 'USD',
                        updatedAt: 20n,
                    }),
                ],
            },
        })

        expect(result).toEqual({ ok: true, newSeq: 4n })
        expect(await storedTransaction(t)).toMatchObject({
            name: 'Lunch',
            currency: 'ARS',
            seq: 5n,
        })
        expect(await pullSince(authed, 4n)).toMatchObject({
            rows: [
                {
                    tableName: 'transactions',
                    row: { id: 't', name: 'Lunch', currency: 'ARS' },
                },
            ],
        })
        expect(await storedConflicts(t)).toEqual([
            {
                tableName: 'transactions',
                entityId: 't',
                reason: 'transaction_currency_mismatch',
                resolution: 'reverted',
                count: 1,
            },
        ])
    })

    it('clears a category the user never had and keeps the rest of the movement', async () => {
        const { t, authed } = await fixture()

        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 2n,
            upserts: { transactions: [transaction({ categoryId: 'unknown' })] },
        })

        expect(result).toEqual({ ok: true, newSeq: 3n })
        expect(await storedTransaction(t)).toMatchObject({
            name: 'Lunch',
            categoryId: '',
            seq: 4n,
        })
        expect(await storedConflicts(t)).toEqual([
            {
                tableName: 'transactions',
                entityId: 't',
                reason: 'transaction_category_missing',
                resolution: 'repaired',
                count: 1,
            },
        ])
    })

    it("keeps an account's currency and the rest of a device's edit", async () => {
        const { t, authed } = await fixture()

        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 2n,
            upserts: {
                accounts: [
                    {
                        id: 'a',
                        name: 'Wallet',
                        currency: 'USD',
                        color: '#000000',
                        icon: 'wallet',
                        isArchived: false,
                        createdAt: 1n,
                        updatedAt: 20n,
                    },
                ],
            },
        })

        expect(result).toEqual({ ok: true, newSeq: 3n })
        const account = await t.run(
            async (ctx) =>
                await ctx.db
                    .query('accounts')
                    .withIndex('by_user_id', (q) =>
                        q.eq('userId', userId).eq('id', 'a'),
                    )
                    .unique(),
        )
        expect(account).toMatchObject({
            name: 'Wallet',
            currency: 'ARS',
            seq: 4n,
        })
        expect(await storedConflicts(t)).toMatchObject([
            { reason: 'account_currency_changed', resolution: 'repaired' },
        ])
    })

    it('moves a tag to the root when its parent is gone, but not when the parent comes later in the batch', async () => {
        const { t, authed } = await fixture()
        await deletedOnAnotherDevice(t, 'tags', 'gone-parent')

        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 2n,
            upserts: {
                tags: [
                    tag('orphan', 'gone-parent'),
                    tag('child', 'parent'),
                    tag('parent'),
                ],
            },
        })

        expect(result).toEqual({ ok: true, newSeq: 3n })
        const tags = await t.run(async (ctx) =>
            (
                await ctx.db
                    .query('tags')
                    .withIndex('by_user_id', (q) => q.eq('userId', userId))
                    .take(10)
            ).map(({ id, parentId, seq }) => ({ id, parentId, seq })),
        )
        expect(tags).toEqual(
            expect.arrayContaining([
                { id: 'orphan', parentId: undefined, seq: 4n },
                { id: 'child', parentId: 'parent', seq: 3n },
                { id: 'parent', parentId: undefined, seq: 3n },
            ]),
        )
        expect(await storedConflicts(t)).toMatchObject([
            {
                entityId: 'orphan',
                reason: 'tag_parent_missing',
                resolution: 'repaired',
            },
        ])
    })

    it('drops a join whose tag was deleted elsewhere', async () => {
        const { t, authed } = await fixture()
        await deletedOnAnotherDevice(t, 'tags', 'gone-tag')

        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 2n,
            upserts: {
                transactions: [transaction()],
                transactionTags: [
                    {
                        id: 't__gone-tag',
                        transactionId: 't',
                        tagId: 'gone-tag',
                        createdAt: 10n,
                        updatedAt: 10n,
                    },
                ],
            },
        })

        expect(result).toEqual({ ok: true, newSeq: 3n })
        expect(await storedTransaction(t)).not.toBeNull()
        expect(await pullSince(authed, 3n)).toMatchObject({
            tombstones: [
                {
                    tableName: 'transactionTags',
                    entityId: 't__gone-tag',
                    seq: 4n,
                },
            ],
        })
        expect(await storedConflicts(t)).toMatchObject([
            { reason: 'join_parent_missing', resolution: 'dropped' },
        ])
    })

    it('sends a merge redirect back to the device that pushed it', async () => {
        const { t, authed } = await fixture()
        await deletedOnAnotherDevice(t, 'accounts', 'merged', 'a')

        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 2n,
            upserts: { transactions: [transaction({ accountId: 'merged' })] },
        })

        expect(result).toEqual({ ok: true, newSeq: 3n })
        // Stored on the live account, at a seq the pusher hasn't acked.
        expect(await pullSince(authed, 3n)).toMatchObject({
            rows: [
                {
                    tableName: 'transactions',
                    row: { id: 't', accountId: 'a', seq: 4n },
                },
            ],
        })
        expect(await storedConflicts(t)).toEqual([])
    })

    it('archives a merged duplicate account at a seq the pusher pulls', async () => {
        const { authed } = await fixture()

        const result = await authed.mutation(api.v1.sync.mutations.push, {
            ...client,
            expectedServerSeq: 2n,
            upserts: {
                accounts: [
                    {
                        id: 'a2',
                        name: 'cash',
                        currency: 'ARS',
                        color: '#000000',
                        icon: 'wallet',
                        isArchived: false,
                        createdAt: 5n,
                        updatedAt: 5n,
                    },
                ],
            },
        })

        expect(result).toEqual({ ok: true, newSeq: 3n })
        expect(await pullSince(authed, 3n)).toMatchObject({
            rows: [
                {
                    tableName: 'accounts',
                    row: { id: 'a2', isArchived: true, seq: 4n },
                },
            ],
        })
    })
})
