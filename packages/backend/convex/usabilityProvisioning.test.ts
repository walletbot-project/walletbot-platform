// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import aggregate from '@convex-dev/aggregate/test'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { api, internal } from './_generated/api'
import type { Id } from './_generated/dataModel'
import {
    accountNamespace,
    inflowsByAccount,
    outflowsByAccount,
} from './aggregates'
import schema from './schema'
import { artMs, parseCivilDay } from './usability/datasets'

// Lives at the convex root: import.meta.glob keys files in the test's own
// directory as `./x.ts`, which convex-test cannot map back to usability/.
const modules = import.meta.glob('./**/*.ts')
const SESSION_DAY = '2026-10-12'
const admin = 'usability-admin'

function fixture() {
    const t = convexTest(schema, modules)
    aggregate.register(t, 'outflowsByAccount')
    aggregate.register(t, 'inflowsByAccount')
    aggregate.register(t, 'transactionsByTag')
    return t
}

async function insertSession(
    t: ReturnType<typeof fixture>,
): Promise<Id<'usabilitySessions'>> {
    return await t.run(async (ctx) => {
        await ctx.db.insert('admins', {
            userId: admin,
            email: 'admin@example.com',
            createdAt: 1n,
        })
        return await ctx.db.insert('usabilitySessions', {
            number: 1,
            group: 1,
            sessionDay: SESSION_DAY,
            password: 'abcdefghjk',
            emailTag: 'abcd',
            status: 'provisioning',
            users: [
                { scenario: 0, userId: 'user-e0', email: 'e0@walletbot.test' },
                { scenario: 1, userId: 'user-e1', email: 'e1@walletbot.test' },
                { scenario: 2, userId: 'user-e2', email: 'e2@walletbot.test' },
            ],
            scenario0Seeded: false,
            scenario2Cursor: 0,
            createdBy: admin,
            createdAt: 1,
        })
    })
}

async function balanceAt(
    t: ReturnType<typeof fixture>,
    userId: string,
    accountName: string,
    untilMs: number,
): Promise<number> {
    return await t.run(async (ctx) => {
        const accounts = await ctx.db
            .query('accounts')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .collect()
        const account = accounts.find((item) => item.name === accountName)
        if (!account) throw new Error(`No account ${accountName}`)
        const namespace = accountNamespace(userId, account.id)
        const bounds = {
            upper: { key: BigInt(untilMs), inclusive: false },
        } as const
        const [outflows, inflows] = await Promise.all([
            outflowsByAccount.sum(ctx, { namespace, bounds }),
            inflowsByAccount.sum(ctx, { namespace, bounds }),
        ])
        return outflows + inflows
    })
}

describe('usability provisioning', () => {
    beforeEach(() => {
        vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
    })
    afterEach(() => {
        vi.unstubAllEnvs()
    })

    it('seeds both scenarios through the regular write path', async () => {
        const t = fixture()
        const sessionId = await insertSession(t)

        await t.mutation(internal.usability.internal.seedScenario0, {
            sessionId,
        })
        await t.mutation(internal.usability.internal.seedScenario2Base, {
            sessionId,
        })
        let batches = 0
        for (;;) {
            const { done } = await t.mutation(
                internal.usability.internal.seedScenario2Batch,
                { sessionId },
            )
            batches += 1
            if (done) break
        }
        expect(batches).toBeGreaterThan(5)

        const day = parseCivilDay(SESSION_DAY)
        if (!day) throw new Error('bad day')
        const sessionStart = artMs(day, 6, 0)

        expect(await balanceAt(t, 'user-e0', 'Efectivo', sessionStart)).toBe(
            4_500_000,
        )
        expect(
            await balanceAt(t, 'user-e0', 'Tarjeta de crédito', sessionStart),
        ).toBe(-25_000_000)
        expect(await balanceAt(t, 'user-e2', 'MercadoPago', sessionStart)).toBe(
            8_732_000,
        )
        expect(await balanceAt(t, 'user-e2', 'Ahorro USD', sessionStart)).toBe(
            260_000,
        )

        const state = await t.run(async (ctx) => {
            const session = await ctx.db.get(sessionId)
            const rules = await ctx.db
                .query('recurrences')
                .withIndex('by_user_archived', (q) =>
                    q.eq('userId', 'user-e2').eq('isArchived', false),
                )
                .collect()
            const joins = await ctx.db
                .query('transactionTags')
                .withIndex('by_user_seq', (q) => q.eq('userId', 'user-e2'))
                .collect()
            const counter = await ctx.db
                .query('syncCounters')
                .withIndex('by_user', (q) => q.eq('userId', 'user-e2'))
                .unique()
            const transactions = await ctx.db
                .query('transactions')
                .withIndex('by_user_seq', (q) => q.eq('userId', 'user-e2'))
                .collect()
            const e1Rows = await ctx.db
                .query('transactions')
                .withIndex('by_user_seq', (q) => q.eq('userId', 'user-e1'))
                .collect()
            return { session, rules, joins, counter, transactions, e1Rows }
        })
        expect(state.session?.scenario0Seeded).toBe(true)
        expect(state.session?.scenario2Answers?.supermarket.totalCents).toBe(
            41_230_000,
        )
        expect(state.rules).toHaveLength(5)
        expect(state.joins).toHaveLength(10)
        for (const join of state.joins) {
            expect(join.id).toBe(`${join.transactionId}__${join.tagId}`)
        }
        const seqs = new Set(state.transactions.map((txn) => txn.seq))
        expect(seqs.size).toBe(state.transactions.length)
        expect(Number(state.counter?.value)).toBe(
            5 + 12 + 4 + 5 + state.transactions.length + state.joins.length,
        )
        const anchors = state.transactions.filter(
            (txn) => txn.recurrenceIndex === 0n,
        )
        expect(anchors).toHaveLength(5)
        expect(state.e1Rows).toHaveLength(0)

        const before = state.transactions.length
        const again = await t.mutation(
            internal.usability.internal.seedScenario2Batch,
            { sessionId },
        )
        expect(again.done).toBe(true)
        await t.mutation(internal.usability.internal.seedScenario0, {
            sessionId,
        })
        const after = await t.run(
            async (ctx) =>
                (
                    await ctx.db
                        .query('transactions')
                        .withIndex('by_user_seq', (q) =>
                            q.eq('userId', 'user-e2'),
                        )
                        .collect()
                ).length,
        )
        expect(after).toBe(before)
    })

    it('validates every field written to a session', async () => {
        const t = fixture()
        const sessionId = await insertSession(t)
        const authed = t.withIdentity({
            subject: admin,
            issuer: 'https://test.convex.site/native-auth',
        })
        const stranger = t.withIdentity({
            subject: 'someone-else',
            issuer: 'https://test.convex.site/native-auth',
        })

        await authed.mutation(api.v1.usability.mutations.setField, {
            sessionId,
            key: 'e0.g1.camino',
            value: ['M', 'T'],
        })
        await expect(
            authed.mutation(api.v1.usability.mutations.setField, {
                sessionId,
                key: 'e0.g1.camino',
                value: ['X'],
            }),
        ).rejects.toThrow()
        await expect(
            authed.mutation(api.v1.usability.mutations.setField, {
                sessionId,
                key: 'not.a.field',
                value: 'x',
            }),
        ).rejects.toThrow()
        await expect(
            authed.mutation(api.v1.usability.mutations.setField, {
                sessionId,
                key: 'sus.1',
                value: 6,
            }),
        ).rejects.toThrow()
        await expect(
            stranger.mutation(api.v1.usability.mutations.setField, {
                sessionId,
                key: 'perfil.edad',
                value: '30',
            }),
        ).rejects.toThrow('Forbidden')
        await expect(
            authed.mutation(api.v1.usability.mutations.stampField, {
                sessionId,
                key: 'perfil.edad',
            }),
        ).rejects.toThrow()

        const stamped = await authed.mutation(
            api.v1.usability.mutations.stampField,
            { sessionId, key: 'e0.inicio' },
        )
        const session = await authed.query(api.v1.usability.queries.get, {
            sessionId,
        })
        expect(session?.fields).toEqual(
            expect.arrayContaining([
                { key: 'e0.g1.camino', value: ['M', 'T'] },
                { key: 'e0.inicio', value: stamped },
            ]),
        )
        expect(
            await authed.query(api.v1.usability.queries.get, {
                sessionId: 'not-an-id',
            }),
        ).toBeNull()
        await expect(
            stranger.query(api.v1.usability.queries.get, { sessionId }),
        ).rejects.toThrow('Forbidden')
    })
})
