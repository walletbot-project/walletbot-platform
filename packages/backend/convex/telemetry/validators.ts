import { v } from 'convex/values'

export const telemetryPlatform = v.union(
    v.literal('ios'),
    v.literal('android'),
    v.literal('web'),
    v.literal('macos'),
    v.literal('windows'),
    v.literal('linux'),
)

export const telemetryEventInput = v.object({
    name: v.string(),
    timestamp: v.number(),
    properties: v.any(),
    installationId: v.optional(v.string()),
    sessionId: v.optional(v.string()),
    userId: v.optional(v.string()),
    appVersion: v.optional(v.string()),
    platform: v.optional(telemetryPlatform),
})

export const metricName = v.union(
    v.literal('business.user_accounts.created_count'),
    v.literal('business.financial_accounts.created_count'),
    v.literal('business.movements.created_count'),
    v.literal('business.transfers.created_count'),
)

export const metricSource = v.union(
    v.literal('web'),
    v.literal('native'),
    v.literal('backend'),
)

export const metricType = v.union(
    v.literal('counter'),
    v.literal('gauge'),
    v.literal('histogram'),
)

export const metricUnit = v.union(v.literal('count'), v.literal('ms'))

export const metricInput = v.object({
    name: metricName,
    timestamp: v.number(),
    source: metricSource,
    type: metricType,
    value: v.number(),
    unit: v.optional(metricUnit),
    attributes: v.optional(v.any()),
    installationId: v.optional(v.string()),
    sessionId: v.optional(v.string()),
    userId: v.optional(v.string()),
    appVersion: v.optional(v.string()),
    platform: v.optional(telemetryPlatform),
})
