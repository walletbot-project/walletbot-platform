import { v } from 'convex/values'
import { internalQuery } from '../_generated/server'

export const pendingForExport = internalQuery({
    args: { limit: v.number() },
    handler: async (ctx, args) => {
        return await ctx.db
            .query('telemetryEvents')
            .withIndex('by_exportStatus_and_receivedAt', (q) =>
                q.eq('exportStatus', 'pending'),
            )
            .take(Math.min(Math.max(args.limit, 1), 100))
    },
})

export const pendingMetricsForExport = internalQuery({
    args: { limit: v.number() },
    handler: async (ctx, args) => {
        return await ctx.db
            .query('telemetryMetrics')
            .withIndex('by_exportStatus_and_receivedAt', (q) =>
                q.eq('exportStatus', 'pending'),
            )
            .take(Math.min(Math.max(args.limit, 1), 100))
    },
})
