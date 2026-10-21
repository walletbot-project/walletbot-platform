// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import rateLimiter from '@convex-dev/rate-limiter/test'
import { convexTest } from 'convex-test'
import { afterEach, expect, it, vi } from 'vitest'
import { api } from './_generated/api'
import schema from './schema'

const modules = import.meta.glob('./**/*.ts')
const account = 'AAAAAAAA-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const client = { platform: 'android', appVersion: '0.7.0', locale: 'es-AR' }

afterEach(() => vi.unstubAllEnvs())

const setup = () => {
    vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
    const t = convexTest(schema, modules)
    rateLimiter.register(t)
    const authed = t.withIdentity({
        subject: 'user',
        issuer: 'https://test.convex.site/native-auth',
    })
    const rows = async () => {
        const result = await t.run(async (ctx) => ({
            feedback: await ctx.db.query('feedback').take(10),
            reports: await ctx.db.query('agentReports').take(10),
        }))
        expect(result.feedback).toHaveLength(1)
        expect(result.reports).toHaveLength(1)
        return result
    }
    return { t, authed, rows }
}

type Caller = ReturnType<typeof setup>['t']

const submitBoth = async (
    caller: Pick<Caller, 'mutation'>,
    identity: { deviceId?: string; localAccountId?: string },
) => {
    expect(
        await caller.mutation(api.v1.feedback.mutations.submit, {
            message: 'the totals are wrong',
            attachments: [],
            ...client,
            ...identity,
        }),
    ).toEqual({ ok: true })
    expect(
        await caller.mutation(api.v1.agentReports.mutations.submit, {
            reason: 'other',
            scope: 'session',
            ...client,
            ...identity,
        }),
    ).toEqual({ ok: true })
}

it('records a local account as its normalized appUserId next to the device', async () => {
    const { t, rows } = setup()
    await submitBoth(t, { deviceId: 'device-1', localAccountId: account })

    const { feedback, reports } = await rows()
    for (const row of [...feedback, ...reports]) {
        expect(row.deviceId).toBe('device-1')
        expect(row.appUserId).toBe(`local:${account.toLowerCase()}`)
        expect(row.userId).toBeUndefined()
    }
})

it('drops a malformed local account id instead of rejecting the submission', async () => {
    const { t, rows } = setup()
    await submitBoth(t, { deviceId: 'device-1', localAccountId: 'not-a-uuid' })

    const { feedback, reports } = await rows()
    for (const row of [...feedback, ...reports]) {
        expect(row.deviceId).toBe('device-1')
        expect(row.appUserId).toBeUndefined()
    }
})

it('leaves a device row without appUserId when no local account is named', async () => {
    const { t, rows } = setup()
    await submitBoth(t, { deviceId: 'device-1' })

    const { feedback, reports } = await rows()
    for (const row of [...feedback, ...reports]) {
        expect(row.deviceId).toBe('device-1')
        expect(row.appUserId).toBeUndefined()
    }
})

it('lets a signed-in identity win over any device or local account it sends', async () => {
    const { authed, rows } = setup()
    await submitBoth(authed, { deviceId: 'device-1', localAccountId: account })

    const { feedback, reports } = await rows()
    for (const row of [...feedback, ...reports]) {
        expect(row.userId).toBe('user')
        expect(row.deviceId).toBeUndefined()
        expect(row.appUserId).toBeUndefined()
    }
})

it('does not register the local account in appUsers', async () => {
    const { t } = setup()
    await submitBoth(t, { deviceId: 'device-1', localAccountId: account })

    const appUsers = await t.run((ctx) => ctx.db.query('appUsers').take(10))
    expect(appUsers).toHaveLength(0)
})
