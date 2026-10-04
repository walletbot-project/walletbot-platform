import { internal } from '../_generated/api'
import type { MutationCtx, QueryCtx } from '../_generated/server'
import { latencyByOperation } from '../aggregates'
import type { MetricInput } from './types'

// Exact p50/p95/p99 for a handful of operations (docs/metrics/
// error-rate-and-latency.md, "Path to p50/p95/p99", option 1). The bucketed
// `*_bucket_count` counters can't produce a percentile, so every sample's raw
// duration is also kept here for a rolling window: one `latencySamples` row
// plus one aggregate entry per segment it belongs to. An hourly cron reads the
// percentiles with `.at(rank)` and exports them as gauges.

export const LATENCY_WINDOW_MS = 24 * 60 * 60 * 1000
const LATENCY_WINDOW_LABEL = '24h'
const ALL_SEGMENTS = 'all'

const LATENCY_QUANTILES = [
    { quantile: 0.5, label: '0.5' },
    { quantile: 0.95, label: '0.95' },
    { quantile: 0.99, label: '0.99' },
] as const

// Rows per push batch. Native caps a chunk at 80 rows
// (`sync_engine.dart:pushChunkLimit`), so `81+` only catches other clients.
export const BATCH_SIZE_BUCKETS = [
    '0-1',
    '2-10',
    '11-40',
    '41-80',
    '81+',
] as const
type BatchSizeBucket = (typeof BATCH_SIZE_BUCKETS)[number]

export const FIRST_RESPONSE_MODES = ['text', 'voice'] as const
type FirstResponseMode = (typeof FIRST_RESPONSE_MODES)[number]

export const LATENCY_OPERATIONS = ['sync_push', 'agent_first_response'] as const

// A batch of 80 rows and a batch of 1 are not the same operation, so push
// samples are segmented by batch size; first responses by text vs voice.
export type LatencySample =
    | {
          operation: 'sync_push'
          segment: BatchSizeBucket
          durationMs: number
      }
    | {
          operation: 'agent_first_response'
          segment: FirstResponseMode
          durationMs: number
      }

export const batchSizeBucket = (rows: number): BatchSizeBucket => {
    if (rows <= 1) return '0-1'
    if (rows <= 10) return '2-10'
    if (rows <= 40) return '11-40'
    if (rows <= 80) return '41-80'
    return '81+'
}

const namespaceOf = (operation: string, segment: string): string =>
    `${operation}:${segment}`

/**
 * Hands the sample to `recordLatencySample` instead of writing it here: the
 * aggregate is shared by every user, so writing it inside the caller's
 * transaction (a sync push) would make unrelated users' pushes conflict on
 * telemetry. Best effort, like every other metric write.
 */
export const scheduleLatencySample = async (
    ctx: MutationCtx,
    sample: LatencySample,
): Promise<void> => {
    if (!Number.isFinite(sample.durationMs) || sample.durationMs < 0) return
    try {
        await ctx.scheduler.runAfter(
            0,
            internal.telemetry.mutations.recordLatencySample,
            { sample },
        )
    } catch (error) {
        console.warn('latency sample failed', {
            operation: sample.operation,
            error: error instanceof Error ? error.message : String(error),
        })
    }
}

export const insertLatencySample = async (
    ctx: MutationCtx,
    sample: LatencySample,
): Promise<void> => {
    const id = await ctx.db.insert('latencySamples', {
        operation: sample.operation,
        segment: sample.segment,
        durationMs: sample.durationMs,
        recordedAt: Date.now(),
    })
    for (const segment of [sample.segment, ALL_SEGMENTS]) {
        await latencyByOperation.insert(ctx, {
            namespace: namespaceOf(sample.operation, segment),
            key: sample.durationMs,
            id,
        })
    }
}

/** Drops samples that left the window, oldest first. */
export const deleteExpiredLatencySamples = async (
    ctx: MutationCtx,
    args: { now: number; limit: number },
): Promise<number> => {
    const rows = await ctx.db
        .query('latencySamples')
        .withIndex('by_recordedAt', (q) =>
            q.lt('recordedAt', args.now - LATENCY_WINDOW_MS),
        )
        .take(args.limit)
    for (const row of rows) {
        for (const segment of [row.segment, ALL_SEGMENTS]) {
            await latencyByOperation.deleteIfExists(ctx, {
                namespace: namespaceOf(row.operation, segment),
                key: row.durationMs,
                id: row._id,
            })
        }
        await ctx.db.delete(row._id)
    }
    return rows.length
}

// Nearest-rank percentile: the smallest sample with at least q of the
// samples at or below it.
const rankOf = (quantile: number, count: number): number =>
    Math.min(count - 1, Math.max(0, Math.ceil(quantile * count) - 1))

const snapshotMetrics = async (
    ctx: QueryCtx,
    args: {
        operation: string
        segment: string
        segmentLabel: 'batch_size' | 'mode'
        timestamp: number
    },
): Promise<MetricInput[]> => {
    const namespace = namespaceOf(args.operation, args.segment)
    const count = await latencyByOperation.count(ctx, { namespace })
    const attributes = {
        operation: args.operation,
        [args.segmentLabel]: args.segment,
        window: LATENCY_WINDOW_LABEL,
    }
    // Always exported, including 0, so a panel can tell "no traffic" from
    // "no data". The percentiles beside it are only as good as this number.
    const metrics: MetricInput[] = [
        {
            name: 'system.latency.samples_count',
            timestamp: args.timestamp,
            source: 'backend',
            type: 'gauge',
            value: count,
            unit: 'count',
            attributes,
        },
    ]
    if (count === 0) return metrics
    for (const { quantile, label } of LATENCY_QUANTILES) {
        const item = await latencyByOperation.at(ctx, rankOf(quantile, count), {
            namespace,
        })
        metrics.push({
            name: 'system.latency.quantile_ms',
            timestamp: args.timestamp,
            source: 'backend',
            type: 'gauge',
            value: item.key,
            unit: 'ms',
            attributes: { ...attributes, quantile: label },
        })
    }
    return metrics
}

/** p50/p95/p99 plus the sample count for every segment, as gauges. */
export const latencySnapshotMetrics = async (
    ctx: QueryCtx,
    timestamp: number,
): Promise<MetricInput[]> => {
    const metrics: MetricInput[] = []
    for (const segment of [ALL_SEGMENTS, ...BATCH_SIZE_BUCKETS]) {
        metrics.push(
            ...(await snapshotMetrics(ctx, {
                operation: 'sync_push',
                segment,
                segmentLabel: 'batch_size',
                timestamp,
            })),
        )
    }
    for (const segment of [ALL_SEGMENTS, ...FIRST_RESPONSE_MODES]) {
        metrics.push(
            ...(await snapshotMetrics(ctx, {
                operation: 'agent_first_response',
                segment,
                segmentLabel: 'mode',
                timestamp,
            })),
        )
    }
    return metrics
}
