import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const agentUsageSamples = defineTable({
    sampleKey: v.string(),
    // Optional actor fields keep pre-WAL-196 user rows valid without backfill.
    userId: v.optional(v.string()),
    actorType: v.optional(
        v.union(v.literal('user'), v.literal('installation')),
    ),
    actorKey: v.optional(v.string()),
    month: v.string(),
    sessionId: v.optional(v.string()),
    interactionId: v.optional(v.string()),
    model: v.string(),
    mode: v.string(),
    costUsd: v.number(),
    occurredAt: v.number(),
    createdAt: v.number(),
})
    .index('by_sampleKey', ['sampleKey'])
    .index('by_user_month', ['userId', 'month'])
    .index('by_actorKey_and_month', ['actorKey', 'month'])
    .index('by_month', ['month'])
    .index('by_createdAt', ['createdAt'])

export const agentUsageMonthly = defineTable({
    key: v.string(),
    // Optional actor fields keep pre-WAL-196 user rows valid without backfill.
    userId: v.optional(v.string()),
    actorType: v.optional(
        v.union(v.literal('user'), v.literal('installation')),
    ),
    actorKey: v.optional(v.string()),
    month: v.string(),
    model: v.string(),
    mode: v.string(),
    estimatedCostUsd: v.number(),
    interactionCount: v.number(),
    updatedAt: v.number(),
})
    .index('by_key', ['key'])
    .index('by_user_month', ['userId', 'month'])
    .index('by_actorKey_and_month', ['actorKey', 'month'])
    .index('by_month', ['month'])
