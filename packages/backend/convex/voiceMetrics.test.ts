// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import { convexTest } from 'convex-test'
import { afterEach, expect, it, vi } from 'vitest'
import { api } from './_generated/api'
import schema from './schema'

const modules = import.meta.glob('./**/*.ts')
afterEach(() => {
    vi.unstubAllEnvs()
    vi.useRealTimers()
})
it('uploads retried web history once and separates model costs across reconnects', async () => {
    vi.useFakeTimers()
    vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
    const t = convexTest(schema, modules)
    const authed = t.withIdentity({
        subject: 'user',
        issuer: 'https://test.convex.site/native-auth',
    })
    const now = BigInt(Date.parse('2026-09-21T00:00:00Z'))
    const batch = {
        ownerId: 'user',
        source: 'web' as const,
        session: {
            id: 'session',
            model: 'gemini-3.8-live',
            status: 'active',
            startedAt: now,
            updatedAt: now,
            endedExplicitly: false,
        },
        events: [
            {
                id: 'u1',
                sequence: 1,
                type: 'usage_metadata',
                direction: 'server',
                occurredAt: now,
                payloadJson: JSON.stringify({
                    model: 'gemini-3.8-live',
                    mode: 'text',
                    promptTokenCount: 1000,
                    responseTokenCount: 1000,
                }),
            },
        ],
    }
    expect(
        await authed.mutation(api.v1.voice.sessions.appendEvents, batch),
    ).toMatchObject({ inserted: 1 })
    expect(
        await authed.mutation(api.v1.voice.sessions.appendEvents, batch),
    ).toMatchObject({ inserted: 0 })
    await authed.mutation(api.v1.voice.sessions.appendEvents, {
        ...batch,
        session: {
            ...batch.session,
            model: 'gemini-3.1-flash-live-preview',
            updatedAt: now + 1n,
        },
        events: [
            {
                ...batch.events[0],
                id: 'u2',
                sequence: 2,
                payloadJson: JSON.stringify({
                    model: 'gemini-3.1-flash-live-preview',
                    mode: 'text',
                    promptTokenCount: 1000,
                    responseTokenCount: 1000,
                }),
            },
        ],
    })
    await t.run(async (ctx) => {
        const samples = await ctx.db.query('agentUsageSamples').take(10)
        expect(samples).toHaveLength(2)
        expect(samples.map((s) => s.model).sort()).toEqual([
            'gemini-3.1-flash-live-preview',
            'gemini-3.8-live',
        ])
        const metrics = await ctx.db.query('telemetryMetrics').take(10)
        expect(metrics).toHaveLength(2)
        expect(
            metrics.every((m) => Math.abs(m.value - 0.00525) < 0.000001),
        ).toBe(true)
    })
    // Native history still has its own metrics transport: don't emit it twice.
    await authed.mutation(api.v1.voice.sessions.appendEvents, {
        ownerId: batch.ownerId,
        session: batch.session,
        events: [{ ...batch.events[0], id: 'native', sequence: 3 }],
    })
    await t.run(async (ctx) => {
        expect(await ctx.db.query('telemetryMetrics').take(10)).toHaveLength(2)
    })
}, 30000)
