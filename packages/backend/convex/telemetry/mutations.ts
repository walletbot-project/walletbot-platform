import { v } from 'convex/values'
import { internal } from '../_generated/api'
import { internalMutation } from '../_generated/server'
import { insertMetricBatch } from './metrics'
import { metricInput, telemetryEventInput } from './validators'

const authMethod = v.union(
    v.literal('email_password'),
    v.literal('google'),
    v.literal('apple'),
    v.literal('local'),
)

const metricSeriesKey = (metric: {
    name: string
    source: string
    unit?: string
    appVersion?: string
    platform?: string
    attributes?: unknown
}): string => {
    const attributes =
        typeof metric.attributes === 'object' &&
        metric.attributes !== null &&
        !Array.isArray(metric.attributes)
            ? Object.fromEntries(
                  Object.entries(metric.attributes).sort(([a], [b]) =>
                      a.localeCompare(b),
                  ),
              )
            : {}

    return JSON.stringify({
        name: metric.name,
        source: metric.source,
        unit: metric.unit ?? '',
        appVersion: metric.appVersion ?? '',
        platform: metric.platform ?? '',
        attributes,
    })
}

export const insertBatch = internalMutation({
    args: {
        events: v.array(telemetryEventInput),
        receivedAt: v.number(),
    },
    handler: async (ctx, args) => {
        for (const event of args.events) {
            await ctx.db.insert('telemetryEvents', {
                ...event,
                receivedAt: args.receivedAt,
                exportStatus: 'pending',
                exportAttempts: 0,
            })
        }

        await ctx.scheduler.runAfter(
            0,
            internal.telemetry.actions.exportPending,
            {},
        )

        return { accepted: args.events.length }
    },
})

export const insertMetricBatchMutation = internalMutation({
    args: {
        metrics: v.array(metricInput),
        receivedAt: v.number(),
    },
    handler: async (ctx, args) => insertMetricBatch(ctx, args),
})

export const recordUserAccountCreated = internalMutation({
    args: {
        userId: v.string(),
        authMethod,
    },
    handler: async (ctx, args) => {
        try {
            return await insertMetricBatch(ctx, {
                receivedAt: Date.now(),
                metrics: [
                    {
                        name: 'business.user_accounts.created_count',
                        timestamp: Date.now(),
                        source: 'backend',
                        type: 'counter',
                        value: 1,
                        unit: 'count',
                        userId: args.userId,
                        attributes: { auth_method: args.authMethod },
                    },
                ],
            })
        } catch (error) {
            console.warn('telemetry metric failed', {
                metric: 'business.user_accounts.created_count',
                userId: args.userId,
                error: error instanceof Error ? error.message : String(error),
            })
            return { accepted: 0 }
        }
    },
})

export const markExported = internalMutation({
    args: { ids: v.array(v.id('telemetryEvents')) },
    handler: async (ctx, args) => {
        for (const id of args.ids) {
            const row = await ctx.db.get(id)
            if (!row || row.exportStatus !== 'exporting') continue
            await ctx.db.patch(id, {
                exportStatus: 'exported',
                lastExportError: undefined,
            })
        }
        return null
    },
})

export const markMetricsExported = internalMutation({
    args: { ids: v.array(v.id('telemetryMetrics')) },
    handler: async (ctx, args) => {
        for (const id of args.ids) {
            const row = await ctx.db.get(id)
            if (!row || row.exportStatus !== 'exporting') continue
            await ctx.db.patch(id, {
                exportStatus: 'exported',
                lastExportError: undefined,
            })
        }
        return null
    },
})

export const markExportFailed = internalMutation({
    args: {
        ids: v.array(v.id('telemetryEvents')),
        error: v.string(),
    },
    handler: async (ctx, args) => {
        for (const id of args.ids) {
            const row = await ctx.db.get(id)
            if (!row || row.exportStatus !== 'exporting') continue
            await ctx.db.patch(id, {
                exportStatus: 'failed',
                exportAttempts: row.exportAttempts + 1,
                lastExportError: args.error.slice(0, 512),
            })
        }
        return null
    },
})

export const markMetricsExportFailed = internalMutation({
    args: {
        ids: v.array(v.id('telemetryMetrics')),
        error: v.string(),
    },
    handler: async (ctx, args) => {
        for (const id of args.ids) {
            const row = await ctx.db.get(id)
            if (!row || row.exportStatus !== 'exporting') continue
            await ctx.db.patch(id, {
                exportStatus: 'failed',
                exportAttempts: row.exportAttempts + 1,
                lastExportError: args.error.slice(0, 512),
            })
        }
        return null
    },
})

export const reserveEventExports = internalMutation({
    args: { limit: v.number() },
    handler: async (ctx, args) => {
        const rows = await ctx.db
            .query('telemetryEvents')
            .withIndex('by_exportStatus_and_receivedAt', (q) =>
                q.eq('exportStatus', 'pending'),
            )
            .take(Math.min(Math.max(args.limit, 1), 100))

        for (const row of rows) {
            await ctx.db.patch(row._id, { exportStatus: 'exporting' })
        }
        return rows.map((row) => ({
            ...row,
            exportStatus: 'exporting' as const,
        }))
    },
})

export const reserveMetricExports = internalMutation({
    args: { limit: v.number() },
    handler: async (ctx, args) => {
        const rows = await ctx.db
            .query('telemetryMetrics')
            .withIndex('by_exportStatus_and_receivedAt', (q) =>
                q.eq('exportStatus', 'pending'),
            )
            .take(Math.min(Math.max(args.limit, 1), 100))

        const reserved = []
        for (const metric of rows) {
            if (
                metric.reservedCumulativeValue !== undefined &&
                metric.reservedCumulativeStartTime !== undefined
            ) {
                await ctx.db.patch(metric._id, { exportStatus: 'exporting' })
                reserved.push({
                    ...metric,
                    exportStatus: 'exporting' as const,
                    cumulativeValue: metric.reservedCumulativeValue,
                    cumulativeStartTime: metric.reservedCumulativeStartTime,
                })
                continue
            }

            const key = metricSeriesKey(metric)
            const existing = await ctx.db
                .query('telemetryMetricSeries')
                .withIndex('by_key', (q) => q.eq('key', key))
                .unique()
            const cumulativeValue =
                (existing?.cumulativeValue ?? 0) + metric.value
            const cumulativeStartTime = existing?.startTime ?? metric.timestamp
            const now = Date.now()

            if (existing) {
                await ctx.db.patch(existing._id, {
                    cumulativeValue,
                    updatedAt: now,
                })
            } else {
                await ctx.db.insert('telemetryMetricSeries', {
                    key,
                    name: metric.name,
                    cumulativeValue,
                    startTime: cumulativeStartTime,
                    updatedAt: now,
                })
            }

            await ctx.db.patch(metric._id, {
                exportStatus: 'exporting',
                reservedCumulativeValue: cumulativeValue,
                reservedCumulativeStartTime: cumulativeStartTime,
            })
            reserved.push({
                ...metric,
                exportStatus: 'exporting' as const,
                reservedCumulativeValue: cumulativeValue,
                reservedCumulativeStartTime: cumulativeStartTime,
                cumulativeValue,
                cumulativeStartTime,
            })
        }
        return reserved
    },
})

export const resetRetryableFailedEvents = internalMutation({
    args: {
        olderThanMs: v.number(),
        maxAttempts: v.number(),
        limit: v.number(),
    },
    handler: async (ctx, args) => {
        const cutoff = Date.now() - args.olderThanMs
        const rows = await ctx.db
            .query('telemetryEvents')
            .withIndex('by_exportStatus_and_receivedAt', (q) =>
                q.eq('exportStatus', 'failed'),
            )
            .take(Math.min(Math.max(args.limit, 1), 100))

        let reset = 0
        for (const row of rows) {
            if (
                row.receivedAt <= cutoff &&
                row.exportAttempts < args.maxAttempts
            ) {
                await ctx.db.patch(row._id, { exportStatus: 'pending' })
                reset += 1
            }
        }
        if (reset > 0) {
            await ctx.scheduler.runAfter(
                0,
                internal.telemetry.actions.exportPending,
                {},
            )
        }
        return { reset }
    },
})

export const resetFailedForRetry = internalMutation({
    args: { ids: v.array(v.id('telemetryEvents')) },
    handler: async (ctx, args) => {
        for (const id of args.ids) {
            await ctx.db.patch(id, { exportStatus: 'pending' })
        }
        return null
    },
})

export const resetMetricsFailedForRetry = internalMutation({
    args: { ids: v.array(v.id('telemetryMetrics')) },
    handler: async (ctx, args) => {
        for (const id of args.ids) {
            await ctx.db.patch(id, { exportStatus: 'pending' })
        }
        return null
    },
})

export const resetRetryableFailedMetrics = internalMutation({
    args: {
        olderThanMs: v.number(),
        maxAttempts: v.number(),
        limit: v.number(),
    },
    handler: async (ctx, args) => {
        const cutoff = Date.now() - args.olderThanMs
        const rows = await ctx.db
            .query('telemetryMetrics')
            .withIndex('by_exportStatus_and_receivedAt', (q) =>
                q.eq('exportStatus', 'failed'),
            )
            .take(Math.min(Math.max(args.limit, 1), 100))

        let reset = 0
        for (const row of rows) {
            if (
                row.receivedAt <= cutoff &&
                row.exportAttempts < args.maxAttempts
            ) {
                await ctx.db.patch(row._id, { exportStatus: 'pending' })
                reset += 1
            }
        }
        return { reset }
    },
})

export const deleteOldExportedMetrics = internalMutation({
    args: {
        olderThanMs: v.number(),
        limit: v.number(),
    },
    handler: async (ctx, args) => {
        const cutoff = Date.now() - args.olderThanMs
        const rows = await ctx.db
            .query('telemetryMetrics')
            .withIndex('by_exportStatus_and_receivedAt', (q) =>
                q.eq('exportStatus', 'exported').lt('receivedAt', cutoff),
            )
            .take(Math.min(Math.max(args.limit, 1), 100))

        for (const row of rows) {
            await ctx.db.delete(row._id)
        }
        return { deleted: rows.length }
    },
})
