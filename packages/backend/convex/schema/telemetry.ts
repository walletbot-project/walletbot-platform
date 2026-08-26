import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const telemetryEvents = defineTable({
    name: v.string(),
    timestamp: v.number(),
    receivedAt: v.number(),
    properties: v.any(),
    installationId: v.optional(v.string()),
    sessionId: v.optional(v.string()),
    sampleId: v.optional(v.string()),
    userId: v.optional(v.string()),
    appVersion: v.optional(v.string()),
    platform: v.optional(
        v.union(
            v.literal('ios'),
            v.literal('android'),
            v.literal('web'),
            v.literal('macos'),
            v.literal('windows'),
            v.literal('linux'),
        ),
    ),
    exportStatus: v.union(
        v.literal('pending'),
        v.literal('exporting'),
        v.literal('exported'),
        v.literal('failed'),
    ),
    exportAttempts: v.number(),
    lastExportError: v.optional(v.string()),
})
    .index('by_receivedAt', ['receivedAt'])
    .index('by_name_and_receivedAt', ['name', 'receivedAt'])
    .index('by_userId_and_receivedAt', ['userId', 'receivedAt'])
    .index('by_exportStatus_and_receivedAt', ['exportStatus', 'receivedAt'])

export const telemetryMetricSeries = defineTable({
    key: v.string(),
    name: v.string(),
    cumulativeValue: v.number(),
    startTime: v.number(),
    updatedAt: v.number(),
})
    .index('by_key', ['key'])
    .index('by_updatedAt', ['updatedAt'])

export const telemetryMetrics = defineTable({
    name: v.union(
        v.literal('business.user_accounts.created_count'),
        v.literal('business.financial_accounts.created_count'),
        v.literal('business.movements.created_count'),
        v.literal('business.transfers.created_count'),
        v.literal('business.users.registered_total'),
        v.literal('business.user_accounts.signed_in_count'),
        v.literal('agent.session.cost_usd'),
        v.literal('agent.interaction.cost_usd'),
        v.literal('agent.user.monthly_cost_usd'),
        v.literal('agent.interactions.completed_count'),
        // Deprecated: accepted only so deployments can clean up historical rows.
        // New ingestion rejects this metric in telemetry validators/catalog.
        v.literal('agent.session.cost_outlier_count'),
        v.literal('agent.session.cost_bucket_count'),
        v.literal('agent.reports.submitted_count'),
    ),
    timestamp: v.number(),
    receivedAt: v.number(),
    source: v.union(
        v.literal('web'),
        v.literal('native'),
        v.literal('backend'),
    ),
    type: v.union(
        v.literal('counter'),
        v.literal('gauge'),
        v.literal('histogram'),
    ),
    value: v.number(),
    unit: v.optional(
        v.union(v.literal('count'), v.literal('ms'), v.literal('usd')),
    ),
    attributes: v.optional(v.any()),
    installationId: v.optional(v.string()),
    sessionId: v.optional(v.string()),
    sampleId: v.optional(v.string()),
    userId: v.optional(v.string()),
    appVersion: v.optional(v.string()),
    platform: v.optional(
        v.union(
            v.literal('ios'),
            v.literal('android'),
            v.literal('web'),
            v.literal('macos'),
            v.literal('windows'),
            v.literal('linux'),
        ),
    ),
    exportStatus: v.union(
        v.literal('pending'),
        v.literal('exporting'),
        v.literal('exported'),
        v.literal('failed'),
    ),
    exportAttempts: v.number(),
    lastExportError: v.optional(v.string()),
    reservedCumulativeValue: v.optional(v.number()),
    reservedCumulativeStartTime: v.optional(v.number()),
})
    .index('by_receivedAt', ['receivedAt'])
    .index('by_name_and_receivedAt', ['name', 'receivedAt'])
    .index('by_userId_and_receivedAt', ['userId', 'receivedAt'])
    .index('by_exportStatus_and_receivedAt', ['exportStatus', 'receivedAt'])
