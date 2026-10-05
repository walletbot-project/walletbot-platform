// @vitest-environment edge-runtime
/// <reference types="vite/client" />
import aggregate from '@convex-dev/aggregate/test'
import { convexTest } from 'convex-test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { internal } from './_generated/api'
import schema from './schema'
import { batchSizeBucket, LATENCY_WINDOW_MS } from './telemetry/latency'

const modules = import.meta.glob('./**/*.ts')
const now = Date.UTC(2026, 9, 3, 12, 0)

function fixture() {
    const t = convexTest(schema, modules)
    aggregate.register(t, 'latencyByOperation')
    return t
}

type Gauge = { name: string; value: number; attributes: unknown }

async function gauges(t: ReturnType<typeof fixture>): Promise<Gauge[]> {
    return await t.run(async (ctx) =>
        (
            await ctx.db
                .query('telemetryMetrics')
                .withIndex('by_name_and_receivedAt', (q) =>
                    q.eq('name', 'system.latency.quantile_ms'),
                )
                .take(100)
        )
            .concat(
                await ctx.db
                    .query('telemetryMetrics')
                    .withIndex('by_name_and_receivedAt', (q) =>
                        q.eq('name', 'system.latency.samples_count'),
                    )
                    .take(100),
            )
            .map((m) => ({
                name: m.name,
                value: m.value,
                attributes: m.attributes,
            })),
    )
}

const pushSample = (
    t: ReturnType<typeof fixture>,
    durationMs: number,
    segment: '0-1' | '41-80',
) =>
    t.mutation(internal.telemetry.mutations.recordLatencySample, {
        sample: { operation: 'sync_push', segment, durationMs },
    })

describe('latency percentiles', { timeout: 30000 }, () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(now)
    })
    afterEach(() => {
        vi.useRealTimers()
    })

    it('buckets batch sizes the way native sizes a chunk', () => {
        expect(batchSizeBucket(0)).toBe('0-1')
        expect(batchSizeBucket(1)).toBe('0-1')
        expect(batchSizeBucket(2)).toBe('2-10')
        expect(batchSizeBucket(40)).toBe('11-40')
        expect(batchSizeBucket(80)).toBe('41-80')
        expect(batchSizeBucket(81)).toBe('81+')
    })

    it('exports exact nearest-rank percentiles with their sample count', async () => {
        const t = fixture()
        // 1..100 ms in a scrambled order: nearest rank gives p50 = 50,
        // p95 = 95, p99 = 99.
        for (let i = 0; i < 100; i++) {
            await pushSample(t, ((i * 37) % 100) + 1, i < 60 ? '0-1' : '41-80')
        }
        await t.mutation(internal.telemetry.mutations.recordLatencyPercentiles)
        const all = await gauges(t)
        const forAll = all.filter(
            (g) =>
                typeof g.attributes === 'object' &&
                g.attributes !== null &&
                'operation' in g.attributes &&
                g.attributes.operation === 'sync_push' &&
                'batch_size' in g.attributes &&
                g.attributes.batch_size === 'all',
        )
        expect(forAll).toEqual(
            expect.arrayContaining([
                {
                    name: 'system.latency.samples_count',
                    value: 100,
                    attributes: {
                        operation: 'sync_push',
                        batch_size: 'all',
                        window: '24h',
                    },
                },
                {
                    name: 'system.latency.quantile_ms',
                    value: 50,
                    attributes: {
                        operation: 'sync_push',
                        batch_size: 'all',
                        window: '24h',
                        quantile: '0.5',
                    },
                },
                {
                    name: 'system.latency.quantile_ms',
                    value: 95,
                    attributes: expect.objectContaining({ quantile: '0.95' }),
                },
                {
                    name: 'system.latency.quantile_ms',
                    value: 99,
                    attributes: expect.objectContaining({ quantile: '0.99' }),
                },
            ]),
        )
        // Each segment is ranked on its own samples only.
        expect(all).toContainEqual({
            name: 'system.latency.samples_count',
            value: 60,
            attributes: {
                operation: 'sync_push',
                batch_size: '0-1',
                window: '24h',
            },
        })
        expect(all).toContainEqual({
            name: 'system.latency.samples_count',
            value: 40,
            attributes: {
                operation: 'sync_push',
                batch_size: '41-80',
                window: '24h',
            },
        })
    })

    it('exports a zero count and no percentiles for a segment without traffic', async () => {
        const t = fixture()
        await t.mutation(internal.telemetry.mutations.recordLatencyPercentiles)
        const all = await gauges(t)
        expect(
            all.filter((g) => g.name === 'system.latency.quantile_ms'),
        ).toEqual([])
        expect(all).toContainEqual({
            name: 'system.latency.samples_count',
            value: 0,
            attributes: {
                operation: 'agent_first_response',
                mode: 'text',
                window: '24h',
            },
        })
    })

    it('ranks text and voice first responses apart, never combined', async () => {
        const t = fixture()
        const firstResponse = (durationMs: number, segment: 'text' | 'voice') =>
            t.mutation(internal.telemetry.mutations.recordLatencySample, {
                sample: {
                    operation: 'agent_first_response',
                    segment,
                    durationMs,
                },
            })
        await firstResponse(1000, 'text')
        await firstResponse(78, 'voice')
        await t.mutation(internal.telemetry.mutations.recordLatencyPercentiles)
        const firstResponseGauges = (await gauges(t)).filter(
            (g) =>
                typeof g.attributes === 'object' &&
                g.attributes !== null &&
                'operation' in g.attributes &&
                g.attributes.operation === 'agent_first_response',
        )
        expect(
            firstResponseGauges.filter(
                (g) =>
                    typeof g.attributes === 'object' &&
                    g.attributes !== null &&
                    'mode' in g.attributes &&
                    g.attributes.mode === 'all',
            ),
        ).toEqual([])
        expect(firstResponseGauges).toContainEqual({
            name: 'system.latency.quantile_ms',
            value: 1000,
            attributes: {
                operation: 'agent_first_response',
                mode: 'text',
                window: '24h',
                quantile: '0.5',
            },
        })
        expect(firstResponseGauges).toContainEqual({
            name: 'system.latency.quantile_ms',
            value: 78,
            attributes: {
                operation: 'agent_first_response',
                mode: 'voice',
                window: '24h',
                quantile: '0.5',
            },
        })
    })

    it('drops samples that left the 24h window, from the table and the aggregate', async () => {
        const t = fixture()
        await pushSample(t, 10, '0-1')
        vi.setSystemTime(now + LATENCY_WINDOW_MS - 1000)
        await pushSample(t, 20, '0-1')
        vi.setSystemTime(now + LATENCY_WINDOW_MS + 1000)

        const result = await t.mutation(
            internal.telemetry.mutations.deleteExpiredLatencySamples,
            { limit: 200 },
        )
        expect(result).toEqual({ deleted: 1 })
        await t.mutation(internal.telemetry.mutations.recordLatencyPercentiles)
        expect(await gauges(t)).toEqual(
            expect.arrayContaining([
                {
                    name: 'system.latency.samples_count',
                    value: 1,
                    attributes: {
                        operation: 'sync_push',
                        batch_size: 'all',
                        window: '24h',
                    },
                },
                {
                    name: 'system.latency.quantile_ms',
                    value: 20,
                    attributes: expect.objectContaining({
                        batch_size: 'all',
                        quantile: '0.99',
                    }),
                },
            ]),
        )
    })
})

describe('first response ingest', { timeout: 30000 }, () => {
    beforeEach(() => {
        vi.useFakeTimers()
        vi.setSystemTime(now)
    })
    afterEach(() => {
        vi.useRealTimers()
    })

    const firstToken = (userId?: string) => ({
        name: 'agent.response.first_token_ms' as const,
        timestamp: now,
        source: 'native' as const,
        type: 'gauge' as const,
        value: 1200,
        unit: 'ms' as const,
        attributes: { mode: 'voice', platform: 'android' },
        installationId: 'install-1',
        ...(userId ? { userId } : {}),
    })

    async function samples(t: ReturnType<typeof fixture>) {
        return await t.run(async (ctx) =>
            (await ctx.db.query('latencySamples').take(10)).map((s) => ({
                operation: s.operation,
                segment: s.segment,
                durationMs: s.durationMs,
            })),
        )
    }

    async function derivedBuckets(t: ReturnType<typeof fixture>) {
        return await t.run(async (ctx) =>
            (
                await ctx.db
                    .query('telemetryMetrics')
                    .withIndex('by_name_and_receivedAt', (q) =>
                        q.eq('name', 'agent.response.first_token_bucket_count'),
                    )
                    .take(10)
            ).map((m) => ({ value: m.value, attributes: m.attributes })),
        )
    }

    it('derives the bucket counter and a percentile sample for an authenticated request', async () => {
        const t = fixture()
        const result = await t.mutation(
            internal.telemetry.mutations.insertMetricBatchMutation,
            { metrics: [firstToken('user-1')], receivedAt: now },
        )
        expect(result).toEqual({ accepted: 2 })
        expect(await derivedBuckets(t)).toEqual([
            {
                value: 1,
                attributes: {
                    bucket: '1000-2500',
                    mode: 'voice',
                    platform: 'android',
                },
            },
        ])
        await t.finishAllScheduledFunctions(vi.runAllTimers)
        expect(await samples(t)).toEqual([
            {
                operation: 'agent_first_response',
                segment: 'voice',
                durationMs: 1200,
            },
        ])
    })

    it('derives the bucket counter but no percentile sample for an anonymous request', async () => {
        const t = fixture()
        await t.mutation(
            internal.telemetry.mutations.insertMetricBatchMutation,
            {
                metrics: [firstToken()],
                receivedAt: now,
            },
        )
        expect(await derivedBuckets(t)).toHaveLength(1)
        await t.finishAllScheduledFunctions(vi.runAllTimers)
        expect(await samples(t)).toEqual([])
    })

    it('accepts the raw metric at the public endpoint and rejects an unknown mode', async () => {
        const t = fixture()
        const post = (attributes: Record<string, string>) =>
            t.fetch('/telemetry/metrics', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    metrics: [{ ...firstToken(), attributes }],
                }),
            })
        const accepted = await post({ mode: 'text', platform: 'ios' })
        expect(accepted.status).toBe(200)
        expect(await accepted.json()).toEqual({ ok: true, accepted: 2 })
        const rejected = await post({ mode: 'mixed', platform: 'ios' })
        expect(rejected.status).toBe(400)
    })
})
