import { internal } from '../_generated/api'
import type { MutationCtx } from '../_generated/server'
import { costBucket, normalizeAgentCostMetric } from './agentPricing'
import type { MetricAttributeValue, MetricInput, MetricName } from './types'
import { usageActor } from './usageActor'

type CreatedBy = 'form' | 'agent'
// Where the write entered the system. `direct_mutation` is the app calling a
// `v1/*` mutation as the signed-in user; `whatsapp` is the server-side agent
// acting for a linked conversation (`agent/tools.ts`), which has no session
// and therefore no `direct_mutation` to attribute it to.
type IngestPath = 'direct_mutation' | 'whatsapp'
type AuthMethod = 'email_password' | 'google' | 'apple' | 'local'

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
    if (!metric.sampleId || metric.value <= 0) return
    const actor = await usageActor(metric)
    if (!actor) return
    // Preserve the exact existing remote keys, including property order, so a
    // retry of a pre-deployment sample cannot be counted a second time.
    const owner =
        actor.actorType === 'user'
            ? { userId: actor.userId }
            : { actorType: actor.actorType, actorKey: actor.actorKey }

    const model = stringAttribute(metric.attributes, 'model') ?? 'unknown'
    const mode = stringAttribute(metric.attributes, 'mode') ?? 'mixed'
    const sampleKey = JSON.stringify({
        ...owner,
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
        ...actor,
        month,
        ...(metric.sessionId ? { sessionId: metric.sessionId } : {}),
        ...(metric.sampleId ? { interactionId: metric.sampleId } : {}),
        model,
        mode,
        costUsd: metric.value,
        occurredAt: metric.timestamp,
        createdAt: now,
    })

    const key = JSON.stringify({ ...owner, month, model, mode })
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
            ...actor,
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
