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
    sampleId: v.optional(v.string()),
    userId: v.optional(v.string()),
    appVersion: v.optional(v.string()),
    platform: v.optional(telemetryPlatform),
})

export const metricName = v.union(
    v.literal('business.user_accounts.created_count'),
    v.literal('business.financial_accounts.created_count'),
    v.literal('business.movements.created_count'),
    v.literal('business.transfers.created_count'),
    v.literal('business.users.registered_total'),
    v.literal('business.user_accounts.signed_in_count'),
    v.literal('agent.sessions.started_count'),
    v.literal('agent.session.cost_usd'),
    v.literal('agent.interaction.cost_usd'),
    v.literal('agent.user.monthly_cost_usd'),
    v.literal('agent.interactions.completed_count'),
    v.literal('agent.session.cost_bucket_count'),
    v.literal('agent.reports.submitted_count'),
    v.literal('sync.errors.count'),
    v.literal('agent.tool.errors.count'),
    v.literal('system.function.duration_bucket_count'),
    v.literal('voice.connect.setup_complete_bucket_count'),
    v.literal('agent.response.first_token_bucket_count'),
    v.literal('agent.response.first_token_ms'),
    v.literal('sync.push.client_failures.count'),
    v.literal('agent.tool.calls.count'),
    v.literal('system.latency.quantile_ms'),
    v.literal('system.latency.samples_count'),
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

export const metricUnit = v.union(
    v.literal('count'),
    v.literal('ms'),
    v.literal('usd'),
)

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
    sampleId: v.optional(v.string()),
    userId: v.optional(v.string()),
    appUserId: v.optional(v.string()),
    appVersion: v.optional(v.string()),
    platform: v.optional(telemetryPlatform),
})
