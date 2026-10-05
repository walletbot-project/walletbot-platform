import { internal } from '../_generated/api'
import type { MutationCtx } from '../_generated/server'
import { costBucket, normalizeAgentCostMetric } from './agentPricing'
import { scheduleLatencySample } from './latency'
import type { MetricAttributeValue, MetricInput, MetricName } from './types'

type CreatedBy = 'form' | 'agent'
// Where the write entered the system. `direct_mutation` is the app calling a
// `v1/*` mutation as the signed-in user; `whatsapp` is the server-side agent
// acting for a linked conversation (`agent/tools.ts`), which has no session
// and therefore no `direct_mutation` to attribute it to.
type IngestPath = 'direct_mutation' | 'whatsapp'
type AuthMethod = 'email_password' | 'google' | 'apple' | 'local'

export type SyncErrorReason =
    | 'client_outdated'
    | 'cursor_mismatch'
    | 'auth_failure'
    | 'validation'
    | 'unknown'
export type AgentToolErrorReason =
    | 'invalid_args'
    | 'not_found'
    | 'provider_error'
    | 'unknown'
export type InstrumentedFunction = 'sync_push' | 'sync_pull' | 'agent_turn'
// `rejected`: a refusal returned as data with no writes (`client_outdated`,
// `cursor_mismatch`); `error`: an exception.
type FunctionStatus = 'ok' | 'rejected' | 'error'

// Mirrors `agentPricing.ts:costBucket` for a plain duration in ms, at the
// bucket boundaries `system.function.duration_bucket_count` uses (a wider,
// coarser scale than the client-side voice-latency buckets).
const functionDurationBucket = (durationMs: number): string => {
    if (durationMs < 100) return '0-100'
    if (durationMs < 250) return '100-250'
    if (durationMs < 500) return '250-500'
    if (durationMs < 1000) return '500-1000'
    if (durationMs < 2500) return '1000-2500'
    if (durationMs < 5000) return '2500-5000'
    return '5000+'
}

// Client-observed latencies (voice connect, first response) use a finer
// scale. Mirrors native `duration_bucket.dart:clientDurationBucket`.
const clientDurationBucket = (durationMs: number): string => {
    if (durationMs < 250) return '0-250'
    if (durationMs < 500) return '250-500'
    if (durationMs < 1000) return '500-1000'
    if (durationMs < 2500) return '1000-2500'
    if (durationMs < 5000) return '2500-5000'
    return '5000+'
}

const monthFromTimestamp = (timestamp: number): string => {
    const date = new Date(timestamp)
    const month = `${date.getUTCMonth() + 1}`.padStart(2, '0')
    return `${date.getUTCFullYear()}-${month}`
}

const stringAttribute = (
    attributes: Record<string, MetricAttributeValue> | undefined,
    key: string,
): string | undefined => {
    const value = attributes?.[key]
    return typeof value === 'string' && value.length > 0 ? value : undefined
}

const recordAgentUsageMonthly = async (
    ctx: MutationCtx,
    metric: MetricInput,
): Promise<void> => {
    if (metric.name !== 'agent.interaction.cost_usd') return
    if (!metric.userId || !metric.sampleId || metric.value <= 0) return

    const model = stringAttribute(metric.attributes, 'model') ?? 'unknown'
    const mode = stringAttribute(metric.attributes, 'mode') ?? 'mixed'
    const sampleKey = JSON.stringify({
        userId: metric.userId,
        metric: metric.name,
        sampleId: metric.sampleId,
    })

    const existingSample = await ctx.db
        .query('agentUsageSamples')
        .withIndex('by_sampleKey', (q) => q.eq('sampleKey', sampleKey))
        .unique()
    if (existingSample) return

    const month = monthFromTimestamp(metric.timestamp)
    const now = Date.now()
    await ctx.db.insert('agentUsageSamples', {
        sampleKey,
        userId: metric.userId,
        month,
        ...(metric.sessionId ? { sessionId: metric.sessionId } : {}),
        ...(metric.sampleId ? { interactionId: metric.sampleId } : {}),
        model,
        mode,
        costUsd: metric.value,
        occurredAt: metric.timestamp,
        createdAt: now,
    })

    const key = JSON.stringify({ userId: metric.userId, month, model, mode })
    const existingRollup = await ctx.db
        .query('agentUsageMonthly')
        .withIndex('by_key', (q) => q.eq('key', key))
        .unique()
    if (existingRollup) {
        await ctx.db.patch(existingRollup._id, {
            estimatedCostUsd: existingRollup.estimatedCostUsd + metric.value,
            interactionCount: existingRollup.interactionCount + 1,
            updatedAt: now,
        })
    } else {
        await ctx.db.insert('agentUsageMonthly', {
            key,
            userId: metric.userId,
            month,
            model,
            mode,
            estimatedCostUsd: metric.value,
            interactionCount: 1,
            updatedAt: now,
        })
    }
}

/**
 * `userId` is optional because not every counter has one: an agent report can
 * come from a native local-only account, which has no backend user at all.
 */
type BackendCounter = {
    name: MetricName
    userId?: string
    attributes: Record<string, MetricAttributeValue>
}

const recordMetric = async (
    ctx: MutationCtx,
    metric: BackendCounter,
): Promise<void> => {
    await ctx.db.insert('telemetryMetrics', {
        name: metric.name,
        timestamp: Date.now(),
        receivedAt: Date.now(),
        source: 'backend',
        type: 'counter',
        value: 1,
        unit: 'count',
        attributes: metric.attributes,
        ...(metric.userId ? { userId: metric.userId } : {}),
        exportStatus: 'pending',
        exportAttempts: 0,
    })

    await ctx.scheduler.runAfter(
        0,
        internal.telemetry.actions.exportPendingMetrics,
        {},
    )
}

const recordMetricSafely = async (
    ctx: MutationCtx,
    metric: BackendCounter,
): Promise<void> => {
    try {
        await recordMetric(ctx, metric)
    } catch (error) {
        console.warn('telemetry metric failed', {
            metric: metric.name,
            userId: metric.userId,
            error: error instanceof Error ? error.message : String(error),
        })
    }
}

export const recordFinancialAccountCreated = (
    ctx: MutationCtx,
    args: { userId: string; createdBy: CreatedBy; ingestPath: IngestPath },
): Promise<void> =>
    recordMetricSafely(ctx, {
        name: 'business.financial_accounts.created_count',
        userId: args.userId,
        attributes: {
            created_by: args.createdBy,
            ingest_path: args.ingestPath,
        },
    })

export const recordUserAccountCreated = (
    ctx: MutationCtx,
    args: { userId: string; authMethod: AuthMethod },
): Promise<void> =>
    recordMetricSafely(ctx, {
        name: 'business.user_accounts.created_count',
        userId: args.userId,
        attributes: { auth_method: args.authMethod },
    })

export const recordMovementCreated = (
    ctx: MutationCtx,
    args: {
        userId: string
        movementType: 'expense' | 'income' | 'balance_adjustment'
        createdBy: CreatedBy
        ingestPath: IngestPath
    },
): Promise<void> =>
    recordMetricSafely(ctx, {
        name: 'business.movements.created_count',
        userId: args.userId,
        attributes: {
            movement_type: args.movementType,
            created_by: args.createdBy,
            ingest_path: args.ingestPath,
        },
    })

export const recordTransferCreated = (
    ctx: MutationCtx,
    args: {
        userId: string
        createdBy: CreatedBy
        ingestPath: IngestPath
        crossCurrency: boolean
    },
): Promise<void> =>
    recordMetricSafely(ctx, {
        name: 'business.transfers.created_count',
        userId: args.userId,
        attributes: {
            created_by: args.createdBy,
            ingest_path: args.ingestPath,
            cross_currency: args.crossCurrency,
        },
    })

/**
 * One reported agent response. Deliberately carries no snapshot and no free
 * text: `telemetryEvents` / `telemetryMetrics` are aggregate analytics and their
 * ingest contract forbids PII, so the conversation content stays in
 * `agentReports` where only an admin can read it.
 */
export const recordAgentReportSubmitted = (
    ctx: MutationCtx,
    args: {
        userId?: string
        reason: string
        scope: string
        clientPlatform: string
    },
): Promise<void> =>
    recordMetricSafely(ctx, {
        name: 'agent.reports.submitted_count',
        ...(args.userId ? { userId: args.userId } : {}),
        attributes: {
            reason: args.reason,
            scope: args.scope,
            client_platform: args.clientPlatform,
        },
    })

/**
 * One emitter per direction. `push` is a mutation and is the only emitter of
 * `direction: 'push'`. `pull` is a query and structurally cannot write (no
 * `ctx.db`/`ctx.scheduler`), so the native client is the only emitter of
 * `direction: 'pull'`, with `source: 'native'` (see
 * `apps/native/lib/sync/sync_engine.dart`).
 */
export const recordSyncError = (
    ctx: MutationCtx,
    args: {
        direction: 'push' | 'pull'
        reason: SyncErrorReason
        platform: string
    },
): Promise<void> =>
    recordMetricSafely(ctx, {
        name: 'sync.errors.count',
        attributes: {
            direction: args.direction,
            reason: args.reason,
            platform: args.platform,
        },
    })

export const recordAgentToolError = (
    ctx: MutationCtx,
    args: { toolName: string; reason: AgentToolErrorReason },
): Promise<void> =>
    recordMetricSafely(ctx, {
        name: 'agent.tool.errors.count',
        attributes: { tool_name: args.toolName, reason: args.reason },
    })

/**
 * One per tool call that reached `agent/tools.ts:execute`: the denominator
 * for `agent.tool.errors.count`. Recorded by `execute` for calls that return
 * and by `agent/runner.ts` for calls that throw (their rollback discards
 * anything `execute` wrote), so each call is counted exactly once.
 */
export const recordAgentToolCall = (
    ctx: MutationCtx,
    args: { toolName: string },
): Promise<void> =>
    recordMetricSafely(ctx, {
        name: 'agent.tool.calls.count',
        attributes: { tool_name: args.toolName },
    })

/**
 * Total call duration only — no DB/external-API breakdown (see
 * docs/metrics/error-rate-and-latency.md, "Traces, eventually"). Reuses the
 * bucket-then-increment-counter shape `insertMetricBatch` already uses for
 * `agent.session.cost_bucket_count` below.
 */
export const recordFunctionDuration = (
    ctx: MutationCtx,
    args: {
        function: InstrumentedFunction
        durationMs: number
        status: FunctionStatus
    },
): Promise<void> =>
    recordMetricSafely(ctx, {
        name: 'system.function.duration_bucket_count',
        attributes: {
            function: args.function,
            bucket: functionDurationBucket(args.durationMs),
            status: args.status,
        },
    })

/**
 * A client reports the raw time to first response; the bucketed counter the
 * distribution panels read is derived here, like `cost_bucket_count` below,
 * so a client sends one metric per response instead of two. Binaries from
 * before `first_token_ms` still send the bucket counter themselves.
 *
 * Only an authenticated request feeds the percentiles: the endpoint also
 * accepts anonymous metrics (R-011), and an anonymous caller must not be able
 * to move the p99.
 */
const recordFirstResponse = async (
    ctx: MutationCtx,
    metric: MetricInput,
    receivedAt: number,
): Promise<number> => {
    if (!Number.isFinite(metric.value) || metric.value < 0) return 0
    const mode = stringAttribute(metric.attributes, 'mode')
    const platform = stringAttribute(metric.attributes, 'platform')
    await ctx.db.insert('telemetryMetrics', {
        name: 'agent.response.first_token_bucket_count',
        timestamp: metric.timestamp,
        receivedAt,
        source: metric.source,
        type: 'counter',
        value: 1,
        unit: 'count',
        attributes: {
            bucket: clientDurationBucket(metric.value),
            ...(mode ? { mode } : {}),
            ...(platform ? { platform } : {}),
        },
        ...(metric.userId ? { userId: metric.userId } : {}),
        ...(metric.sessionId ? { sessionId: metric.sessionId } : {}),
        ...(metric.installationId
            ? { installationId: metric.installationId }
            : {}),
        ...(metric.appVersion ? { appVersion: metric.appVersion } : {}),
        ...(metric.platform ? { platform: metric.platform } : {}),
        exportStatus: 'pending',
        exportAttempts: 0,
    })
    if (metric.userId && (mode === 'text' || mode === 'voice')) {
        await scheduleLatencySample(ctx, {
            operation: 'agent_first_response',
            segment: mode,
            durationMs: metric.value,
        })
    }
    return 1
}

export const insertMetricBatch = async (
    ctx: MutationCtx,
    args: { metrics: MetricInput[]; receivedAt: number },
): Promise<{ accepted: number }> => {
    let accepted = 0
    for (const metric of args.metrics) {
        const normalizedMetric = normalizeAgentCostMetric(metric)
        if (!normalizedMetric) continue

        await recordAgentUsageMonthly(ctx, normalizedMetric)
        await ctx.db.insert('telemetryMetrics', {
            ...normalizedMetric,
            receivedAt: args.receivedAt,
            exportStatus: 'pending',
            exportAttempts: 0,
        })
        accepted += 1

        if (normalizedMetric.name === 'agent.response.first_token_ms') {
            accepted += await recordFirstResponse(
                ctx,
                normalizedMetric,
                args.receivedAt,
            )
        }

        if (normalizedMetric.name === 'agent.session.cost_usd') {
            await ctx.db.insert('telemetryMetrics', {
                name: 'agent.session.cost_bucket_count',
                timestamp: normalizedMetric.timestamp,
                receivedAt: args.receivedAt,
                source: normalizedMetric.source,
                type: 'counter',
                value: 1,
                unit: 'count',
                attributes: {
                    model:
                        stringAttribute(normalizedMetric.attributes, 'model') ??
                        'unknown',
                    mode:
                        stringAttribute(normalizedMetric.attributes, 'mode') ??
                        'mixed',
                    cost_bucket: costBucket(normalizedMetric.value),
                },
                ...(normalizedMetric.userId
                    ? { userId: normalizedMetric.userId }
                    : {}),
                ...(normalizedMetric.sessionId
                    ? { sessionId: normalizedMetric.sessionId }
                    : {}),
                ...(normalizedMetric.installationId
                    ? { installationId: normalizedMetric.installationId }
                    : {}),
                ...(normalizedMetric.appVersion
                    ? { appVersion: normalizedMetric.appVersion }
                    : {}),
                ...(normalizedMetric.platform
                    ? { platform: normalizedMetric.platform }
                    : {}),
                exportStatus: 'pending',
                exportAttempts: 0,
            })
            accepted += 1
        }
    }

    await ctx.scheduler.runAfter(
        0,
        internal.telemetry.actions.exportPendingMetrics,
        {},
    )

    return { accepted }
}
