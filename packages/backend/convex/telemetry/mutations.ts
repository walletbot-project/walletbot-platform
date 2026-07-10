import { v } from 'convex/values'
import { internal } from '../_generated/api'
import { internalMutation } from '../_generated/server'
import { telemetryEventInput } from './validators'

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

export const markExported = internalMutation({
    args: { ids: v.array(v.id('telemetryEvents')) },
    handler: async (ctx, args) => {
        for (const id of args.ids) {
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
            if (!row) continue
            await ctx.db.patch(id, {
                exportStatus: 'failed',
                exportAttempts: row.exportAttempts + 1,
                lastExportError: args.error.slice(0, 512),
            })
        }
        return null
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
