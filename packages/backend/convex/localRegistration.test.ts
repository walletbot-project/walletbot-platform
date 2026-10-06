// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import rateLimiter from '@convex-dev/rate-limiter/test'
import { convexTest } from 'convex-test'
import { afterEach, expect, it, vi } from 'vitest'
import { internal } from './_generated/api'
import { createLiveToken } from './live/createToken'
import schema from './schema'

vi.mock('./live/createToken', () => ({ createLiveToken: vi.fn() }))
const modules = import.meta.glob('./**/*.ts')
const account = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
afterEach(() => {
    vi.useRealTimers()
    vi.resetAllMocks()
})

it('registers the account before minting, repeats idempotently and respects the mint gate', async () => {
    vi.useFakeTimers()
    const t = convexTest(schema, modules)
    rateLimiter.register(t)
    vi.mocked(createLiveToken).mockImplementation(async () => {
        await t.run(async (ctx) => {
            const row = await ctx.db
                .query('appUsers')
                .withIndex('by_appUserId', (q) =>
                    q.eq('appUserId', `local:${account}`),
                )
                .unique()
            expect(row?.type).toBe('local')
        })
        return {
            token: 'fake-token',
            expireTime: 'later',
            model: 'gemini-3.8-live',
            timings: { googleMs: 0, mintMs: 0, moduleAgeMs: 0 },
        }
    })
    const mint = () =>
        t.fetch('/v1/live/token', {
            method: 'POST',
            body: JSON.stringify({
                deviceId: 'device-origin',
                localAccountId: account,
            }),
        })
    expect((await mint()).status).toBe(200)
    expect((await mint()).status).toBe(200)
    await t.run(async (ctx) => {
        expect(await ctx.db.query('appUsers').take(10)).toHaveLength(1)
        await ctx.db.insert('featureFlags', {
            key: 'agentLocalAccounts',
            description: '',
            enabledByDefault: false,
            updatedAt: 0n,
            updatedBy: 'test',
        })
    })
    expect((await mint()).status).toBe(403)
    expect(createLiveToken).toHaveBeenCalledTimes(2)
})

it('does not downgrade an identity already linked to a registered user', async () => {
    const t = convexTest(schema, modules)
    const args = { deviceId: 'device-origin', localAccountId: account }
    await t.mutation(internal.appUsers.internal.registerLocal, args)
    await t.run(async (ctx) => {
        const row = await ctx.db.query('appUsers').take(1)
        await ctx.db.patch(row[0]._id, {
            type: 'registered',
            userId: 'registered-user',
        })
    })
    expect(
        await t.mutation(internal.appUsers.internal.registerLocal, args),
    ).toEqual({ ok: false, error: 'not_local' })
    await t.run(async (ctx) => {
        const rows = await ctx.db.query('appUsers').take(10)
        expect(rows).toHaveLength(1)
        expect(rows[0]).toMatchObject({
            appUserId: `local:${account}`,
            type: 'registered',
            userId: 'registered-user',
        })
    })
})
