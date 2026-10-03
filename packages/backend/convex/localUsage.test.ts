// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { api, internal } from './_generated/api'
import schema from './schema'
import type { MetricInput } from './telemetry/types'

const modules = import.meta.glob('./**/*.ts')
const month = '2026-10'
const installationId = 'eeeb0b51-959e-4e9e-84c1-c53c49d88415'
const sample = (overrides: Partial<MetricInput> = {}): MetricInput => ({
    name: 'agent.interaction.cost_usd',
    timestamp: Date.parse('2026-10-03T12:00:00Z'),
    source: 'native',
    type: 'gauge',
    value: 999, // The server must reprice this from tokens.
    unit: 'usd',
    installationId,
    sampleId: 'interaction-1',
    attributes: {
        model: 'gemini-3.8-live',
        mode: 'text',
        cost_source: 'provider_usage',
        token_input_text: 1000,
        token_output_text: 1000,
    },
    ...overrides,
})
const post = (
    t: Pick<ReturnType<typeof convexTest>, 'fetch'>,
    metrics: unknown[],
    authenticated = false,
) =>
    t.fetch('/telemetry/metrics', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            ...(authenticated ? { Authorization: 'Bearer test-token' } : {}),
        },
        body: JSON.stringify({ metrics }),
    })

beforeEach(() => {
    vi.useFakeTimers()
    vi.stubEnv('CONVEX_SITE_URL', 'https://test.convex.site')
})
afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllEnvs()
    vi.unstubAllGlobals()
})

it('ingests local costs once per installation and keeps financial data local', async () => {
    const t = convexTest(schema, modules)
    for (const metric of [
        sample(),
        sample(),
        sample({ sampleId: 'interaction-2' }),
        sample({ installationId: 'another-installation' }),
    ]) {
        const response = await post(t, [metric])
        expect(response.status).toBe(200)
    }
    await t.run(async (ctx) => {
        const samples = await ctx.db.query('agentUsageSamples').take(10)
        expect(samples).toHaveLength(3)
        expect(
            samples.every(
                (s) => s.actorType === 'installation' && s.userId === undefined,
            ),
        ).toBe(true)
        expect(samples.every((s) => Math.abs(s.costUsd - 0.00525) < 1e-9)).toBe(
            true,
        )
        expect(JSON.stringify(samples)).not.toContain(installationId)
        const rows = await ctx.db.query('agentUsageMonthly').take(10)
        expect(rows).toHaveLength(2)
        expect(rows.map((r) => r.interactionCount).sort()).toEqual([1, 2])
        expect(
            rows.reduce((total, r) => total + r.estimatedCostUsd, 0),
        ).toBeCloseTo(0.01575)
        for (const table of [
            'accounts',
            'transactions',
            'categories',
            'tags',
            'savedFilters',
            'dashboardWidgets',
            'agentMemories',
            'voiceSessions',
            'voiceSessionEvents',
        ] as const) {
            expect(await ctx.db.query(table).take(1)).toEqual([])
        }
    })
}, 30000)

it('uses only server-authenticated users and isolates their monthly query', async () => {
    const t = convexTest(schema, modules)
    const remote = t.withIdentity({
        subject: 'remote-user',
        issuer: 'https://test.convex.site/native-auth',
    })
    expect((await post(t, [sample({ userId: 'remote-user' })])).status).toBe(
        200,
    )
    expect(
        (await post(remote, [sample({ userId: 'forged-user' })], true)).status,
    ).toBe(200)
    expect((await post(remote, [sample()], true)).status).toBe(200)
    const usage = await remote.query(api.agentUsage.queries.myMonthlyUsage, {
        month,
    })
    expect(usage.interactionCount).toBe(1)
    expect(usage.estimatedCostUsd).toBeCloseTo(0.00525)
    const other = t.withIdentity({
        subject: 'other-user',
        issuer: 'https://test.convex.site/native-auth',
    })
    expect(
        (await other.query(api.agentUsage.queries.myMonthlyUsage, { month }))
            .interactionCount,
    ).toBe(0)
    expect((await post(t, [sample()], true)).status).toBe(401)
    await t.run(async (ctx) => {
        const rows = await ctx.db.query('agentUsageMonthly').take(10)
        expect(rows).toHaveLength(2)
        expect(rows.map((r) => r.actorType).sort()).toEqual([
            'installation',
            'user',
        ])
        expect(rows.find((r) => r.actorType === 'user')?.userId).toBe(
            'remote-user',
        )
    })
})

it('rejects missing or malformed anonymous IDs without creating usage', async () => {
    const t = convexTest(schema, modules)
    for (const id of [
        undefined,
        '',
        'short',
        'a'.repeat(129),
        'some@email.com',
    ]) {
        expect((await post(t, [sample({ installationId: id })])).status).toBe(
            400,
        )
    }
    await t.run(async (ctx) => {
        expect(await ctx.db.query('agentUsageMonthly').take(1)).toEqual([])
    })
})

it('retains pre-deployment remote idempotency keys and rollups', async () => {
    const t = convexTest(schema, modules)
    const metric = sample({ userId: 'legacy-user' })
    await t.run(async (ctx) => {
        await ctx.db.insert('agentUsageSamples', {
            sampleKey: JSON.stringify({
                userId: metric.userId,
                metric: metric.name,
                sampleId: metric.sampleId,
            }),
            userId: 'legacy-user',
            month,
            model: 'gemini-3.8-live',
            mode: 'text',
            costUsd: 0.00525,
            occurredAt: metric.timestamp,
            createdAt: metric.timestamp,
        })
        await ctx.db.insert('agentUsageMonthly', {
            key: JSON.stringify({
                userId: metric.userId,
                month,
                model: 'gemini-3.8-live',
                mode: 'text',
            }),
            userId: 'legacy-user',
            month,
            model: 'gemini-3.8-live',
            mode: 'text',
            estimatedCostUsd: 0.00525,
            interactionCount: 1,
            updatedAt: metric.timestamp,
        })
    })
    await t.mutation(internal.telemetry.mutations.insertMetricBatchMutation, {
        metrics: [metric],
        receivedAt: metric.timestamp,
    })
    await t.mutation(internal.telemetry.mutations.insertMetricBatchMutation, {
        metrics: [{ ...metric, sampleId: 'new-interaction' }],
        receivedAt: metric.timestamp,
    })
    const rows = await t.query(
        internal.agentUsage.queries.listMonthlyUsageForTelemetry,
        { month },
    )
    expect(rows).toHaveLength(1)
    expect(rows[0]).toMatchObject({
        userId: 'legacy-user',
        actorType: 'user',
        interactionCount: 2,
    })
    expect(rows[0].estimatedCostUsd).toBeCloseTo(0.0105)
})

it('exports a bounded ranking for both scopes with pseudonyms and environment', async () => {
    const t = convexTest(schema, modules)
    const metrics = [
        sample(),
        ...Array.from({ length: 22 }, (_, i) =>
            sample({ userId: `remote-${i}` }),
        ),
    ]
    await t.mutation(internal.telemetry.mutations.insertMetricBatchMutation, {
        metrics,
        receivedAt: Date.now(),
    })
    // Exclude raw ingest rows to inspect the snapshot export in isolation.
    await t.run(async (ctx) => {
        for (const row of await ctx.db.query('telemetryMetrics').take(50))
            await ctx.db.delete(row._id)
    })
    const result = await t.action(
        internal.telemetry.actions.recordAgentMonthlyUsageNow,
        { month },
    )
    expect(result).toMatchObject({ rows: 23, exportedRows: 21, accepted: 21 })
    vi.stubEnv(
        'OTEL_EXPORTER_OTLP_METRICS_ENDPOINT',
        'https://metrics.test/v1/metrics',
    )
    vi.stubEnv('WALLETBOT_ENV', 'test-local-usage')
    const fetchMock = vi
        .fn()
        .mockResolvedValue(new Response('{}', { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)
    expect(
        await t.action(internal.telemetry.actions.exportPendingMetrics, {}),
    ).toEqual({ exported: 21 })
    const payload = JSON.parse(fetchMock.mock.calls[0][1].body)
    const resource = payload.resourceMetrics[0]
    expect(resource.resource.attributes).toContainEqual({
        key: 'deployment.environment',
        value: { stringValue: 'test-local-usage' },
    })
    const points = resource.scopeMetrics[0].metrics.map(
        (m: {
            gauge: {
                dataPoints: Array<{
                    attributes: Array<{
                        key: string
                        value: { stringValue: string }
                    }>
                }>
            }
        }) => m.gauge.dataPoints[0],
    )
    const scopes = points.map(
        (p: {
            attributes: Array<{ key: string; value: { stringValue: string } }>
        }) =>
            p.attributes.find((a) => a.key === 'account_scope')?.value
                .stringValue,
    )
    expect(scopes.filter((s: string) => s === 'local')).toHaveLength(1)
    expect(scopes.filter((s: string) => s === 'remote')).toHaveLength(20)
    for (const point of points) {
        expect(
            point.attributes.find((a: { key: string }) => a.key === 'user_hash')
                .value.stringValue,
        ).toMatch(/^[0-9a-f]{24}$/)
    }
    const encoded = JSON.stringify(payload)
    expect(encoded).not.toContain(installationId)
    expect(encoded).not.toContain('remote-')
    expect(encoded).not.toContain('installation:')
})

it('keeps local month/model rollups separate and skips missing samples', async () => {
    const t = convexTest(schema, modules)
    await t.mutation(internal.telemetry.mutations.insertMetricBatchMutation, {
        receivedAt: Date.now(),
        metrics: [
            sample(),
            sample({
                sampleId: 'next-month',
                timestamp: Date.parse('2026-11-01T00:00:00Z'),
            }),
            sample({
                sampleId: 'other-model',
                attributes: {
                    ...sample().attributes,
                    model: 'gemini-3.1-flash-live-preview',
                },
            }),
            sample({ sampleId: undefined }),
            sample({ sampleId: 'no-identity', installationId: undefined }),
            sample({
                sampleId: 'zero',
                attributes: { model: 'gemini-3.8-live', mode: 'text' },
                value: 0,
            }),
        ],
    })
    const october = await t.query(
        internal.agentUsage.queries.listMonthlyUsageForTelemetry,
        { month },
    )
    const november = await t.query(
        internal.agentUsage.queries.listMonthlyUsageForTelemetry,
        { month: '2026-11' },
    )
    expect(october).toHaveLength(2)
    expect(november).toHaveLength(1)
    expect(new Set([...october, ...november].map((r) => r.actorKey)).size).toBe(
        1,
    )
    expect(
        [...october, ...november].every((r) => r.interactionCount === 1),
    ).toBe(true)
})
