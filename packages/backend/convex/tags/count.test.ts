// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import aggregate from '@convex-dev/aggregate/test'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { api } from '../_generated/api'
import schema from '../schema'

const modules = import.meta.glob('../**/*.ts')
const now = Date.UTC(2026, 8, 13, 12, 0)
const userId = 'tag-count-user'

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
            name: 'Rent',
            color: '#000000',
            icon: 'home',
            isArchived: false,
            createdAt: 1n,
            updatedAt: 1n,
            seq: 2n,
        })
        await ctx.db.insert('tags', {
            userId,
            id: 'tag',
            name: 'Monthly',
            color: '#000000',
            isArchived: false,
            createdAt: 1n,
            updatedAt: 1n,
            seq: 3n,
        })
        await ctx.db.insert('syncCounters', { userId, value: 3n })
    })
    const expense = (id: string, date: number) =>
        authed.mutation(api.v1.transactions.mutations.createExpense, {
            id,
            name: id,
            amount: 1000n,
            accountId: 'a',
            categoryId: 'c',
            date: BigInt(date),
            dateConfirmed: true,
        })
    const count = async () => {
        const tags = await authed.query(
            api.v1.tags.queries.listActiveWithCounts,
            { asOfMs: BigInt(now) },
        )
        return tags.find((tag) => tag.id === 'tag')?.transactionCount
    }
    return { t, authed, expense, count }
}

describe('tag counts come from the aggregate', { timeout: 30000 }, () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(now)
        vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
    })
    afterEach(() => {
        vi.useRealTimers()
        vi.unstubAllEnvs()
    })
    it('follows attach, date edits, detach and archive', async () => {
        const { authed, expense, count } = await fixture()
        await expense('past', now - 1000)
        await expense('future', now + 3600000)
        expect(await count()).toBe(0)

        await authed.mutation(api.v1.transactions.mutations.update, {
            id: 'past',
            addTagIds: ['tag'],
        })
        await authed.mutation(api.v1.transactions.mutations.update, {
            id: 'future',
            addTagIds: ['tag'],
        })
        // The future one is tagged but has not happened.
        expect(await count()).toBe(1)

        await authed.mutation(api.v1.transactions.mutations.update, {
            id: 'future',
            date: BigInt(now - 2000),
        })
        expect(await count()).toBe(2)

        await authed.mutation(api.v1.transactions.mutations.update, {
            id: 'past',
            removeTagIds: ['tag'],
        })
        expect(await count()).toBe(1)

        await authed.mutation(api.v1.transactions.mutations.archive, {
            id: 'future',
        })
        expect(await count()).toBe(0)
    })
})

describe('recurrence per-call cap', { timeout: 30000 }, () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(now)
        vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
    })
    afterEach(() => {
        vi.useRealTimers()
        vi.unstubAllEnvs()
    })
    it('rejects an oversized series before writing anything', async () => {
        const { t, authed } = await fixture()
        await expect(
            authed.mutation(api.v1.recurrences.mutations.create, {
                recurrenceId: 'r',
                frequency: 'daily',
                endDate: BigInt(Date.UTC(2050, 0, 1)),
                transactionId: 't',
                type: 'expense',
                name: 'Coffee',
                amount: 1000n,
                accountId: 'a',
                categoryId: 'c',
                date: BigInt(now),
                dateConfirmed: true,
            }),
        ).rejects.toThrow(/maximum is 2500/)
        await t.run(async (ctx) => {
            expect(await ctx.db.query('recurrences').collect()).toEqual([])
            expect(await ctx.db.query('transactions').collect()).toEqual([])
        })
    })
})
