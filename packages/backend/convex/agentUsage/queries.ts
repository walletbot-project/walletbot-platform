import { v } from 'convex/values'
import { internalQuery, query } from '../_generated/server'
import { requireAuth } from '../users/helpers'

const currentMonth = () => {
    const date = new Date()
    const month = `${date.getUTCMonth() + 1}`.padStart(2, '0')
    return `${date.getUTCFullYear()}-${month}`
}

export const myMonthlyUsage = query({
    args: { month: v.optional(v.string()) },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const month = args.month ?? currentMonth()
        const rows = await ctx.db
            .query('agentUsageMonthly')
            .withIndex('by_user_month', (q) =>
                q.eq('userId', userId).eq('month', month),
            )
            .collect()
        return {
            month,
            estimatedCostUsd: rows.reduce(
                (total, row) => total + row.estimatedCostUsd,
                0,
            ),
            interactionCount: rows.reduce(
                (total, row) => total + row.interactionCount,
                0,
            ),
            breakdown: rows.map((row) => ({
                model: row.model,
                mode: row.mode,
                estimatedCostUsd: row.estimatedCostUsd,
                interactionCount: row.interactionCount,
                updatedAt: row.updatedAt,
            })),
        }
    },
})

export const listMonthlyUsageForTelemetry = internalQuery({
    args: { month: v.optional(v.string()) },
    handler: async (ctx, args) => {
        const month = args.month ?? currentMonth()
        const rows = await ctx.db
            .query('agentUsageMonthly')
            .withIndex('by_month', (q) => q.eq('month', month))
            .collect()
        return rows.map((row) => ({
            userId: row.userId,
            parentId: row.parentId,
            actorType: row.actorType ?? 'user',
            actorKey: row.actorKey ?? `user:${row.userId}`,
            month: row.month,
            model: row.model,
            mode: row.mode,
            estimatedCostUsd: row.estimatedCostUsd,
            interactionCount: row.interactionCount,
            updatedAt: row.updatedAt,
        }))
    },
})
