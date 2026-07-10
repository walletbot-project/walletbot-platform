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
