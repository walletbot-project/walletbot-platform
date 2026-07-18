import { internal } from '../_generated/api'
import type { MutationCtx } from '../_generated/server'
import type { MetricAttributeValue, MetricInput, MetricName } from './types'

type CreatedBy = 'form' | 'agent'
type IngestPath = 'direct_mutation' | 'sync_push'
type AuthMethod = 'email_password' | 'google' | 'apple' | 'local'

export const tagCountBucket = (count: number): string => {
    if (count <= 0) return '0'
    if (count === 1) return '1'
    if (count <= 3) return '2-3'
    return '4+'
}

const recordMetric = async (
    ctx: MutationCtx,
    metric: {
        name: MetricName
        userId: string
        attributes: Record<string, MetricAttributeValue>
    },
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
        userId: metric.userId,
        exportStatus: 'pending',
        exportAttempts: 0,
    })

    await ctx.scheduler.runAfter(
        0,
        internal.telemetry.actions.exportPendingMetrics,
        {},
    )
}

export const recordFinancialAccountCreated = (
    ctx: MutationCtx,
    args: { userId: string; createdBy: CreatedBy; ingestPath: IngestPath },
): Promise<void> =>
    recordMetric(ctx, {
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
    recordMetric(ctx, {
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
        tagCount: number
    },
): Promise<void> =>
    recordMetric(ctx, {
        name: 'business.movements.created_count',
        userId: args.userId,
        attributes: {
            movement_type: args.movementType,
            created_by: args.createdBy,
            ingest_path: args.ingestPath,
            tag_count_bucket: tagCountBucket(args.tagCount),
        },
    })

export const recordTransferCreated = (
    ctx: MutationCtx,
    args: {
        userId: string
        createdBy: CreatedBy
        ingestPath: IngestPath
        crossCurrency: boolean
        tagCount: number
    },
): Promise<void> =>
    recordMetric(ctx, {
        name: 'business.transfers.created_count',
        userId: args.userId,
        attributes: {
            created_by: args.createdBy,
            ingest_path: args.ingestPath,
            cross_currency: args.crossCurrency,
            tag_count_bucket: tagCountBucket(args.tagCount),
        },
    })

export const insertMetricBatch = async (
    ctx: MutationCtx,
    args: { metrics: MetricInput[]; receivedAt: number },
): Promise<{ accepted: number }> => {
    for (const metric of args.metrics) {
        await ctx.db.insert('telemetryMetrics', {
            ...metric,
            receivedAt: args.receivedAt,
            exportStatus: 'pending',
            exportAttempts: 0,
        })
    }

    await ctx.scheduler.runAfter(
        0,
        internal.telemetry.actions.exportPendingMetrics,
        {},
    )

    return { accepted: args.metrics.length }
}
