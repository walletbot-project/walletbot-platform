import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const telemetryEvents = defineTable({
    name: v.string(),
    timestamp: v.number(),
    receivedAt: v.number(),
    properties: v.any(),
    installationId: v.optional(v.string()),
    sessionId: v.optional(v.string()),
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
