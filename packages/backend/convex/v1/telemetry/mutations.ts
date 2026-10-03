import { v } from 'convex/values'
import { mutation } from '../../_generated/server'
import { insertMetricBatch } from '../../telemetry/metrics'
import { normalizeMetric } from '../../telemetry/metricValidation'
import type { MetricInput } from '../../telemetry/types'
import {
    metricName,
    metricSource,
    metricType,
    metricUnit,
    telemetryPlatform,
} from '../../telemetry/validators'
import { requireAuth } from '../../users/helpers'

const webMetricInput = v.object({
    name: metricName,
    timestamp: v.number(),
    source: metricSource,
    type: metricType,
    value: v.number(),
    unit: v.optional(metricUnit),
    attributes: v.optional(
        v.record(v.string(), v.union(v.string(), v.number(), v.boolean())),
    ),
    installationId: v.optional(v.string()),
    sessionId: v.optional(v.string()),
    sampleId: v.optional(v.string()),
    appVersion: v.optional(v.string()),
    platform: v.optional(telemetryPlatform),
})

const webMetricNames = new Set([
    'agent.sessions.started_count',
    'agent.session.cost_usd',
    'agent.interaction.cost_usd',
    'agent.interactions.completed_count',
])

const assertWebMetric = (metric: MetricInput): void => {
    if (!webMetricNames.has(metric.name)) {
        throw new Error(`metric ${metric.name} is not accepted from web`)
    }
    if (metric.value <= 0) {
        throw new Error(`metric ${metric.name} must have a positive value`)
    }
    if (
        (metric.name === 'agent.sessions.started_count' ||
            metric.name === 'agent.interactions.completed_count') &&
        metric.value !== 1
    ) {
        throw new Error(`metric ${metric.name} must increment by one`)
    }
    if (!metric.sessionId) {
        throw new Error(`metric ${metric.name} requires sessionId`)
    }
    if (metric.name === 'agent.interaction.cost_usd' && !metric.sampleId) {
        throw new Error(`metric ${metric.name} requires sampleId`)
    }
    const attributes = metric.attributes ?? {}
    if (Object.keys(attributes).length > 32) {
        throw new Error(`metric ${metric.name} has too many attributes`)
    }
    if (typeof attributes.model !== 'string' || !attributes.model.trim()) {
        throw new Error(`metric ${metric.name} requires model`)
    }
    if (
        metric.name !== 'agent.sessions.started_count' &&
        typeof attributes.mode !== 'string'
    ) {
        throw new Error(`metric ${metric.name} requires mode`)
    }
    if (
        metric.name === 'agent.sessions.started_count' &&
        typeof attributes.start_kind !== 'string'
    ) {
        throw new Error(`metric ${metric.name} requires start_kind`)
    }
    if (
        metric.name === 'agent.interactions.completed_count' &&
        typeof attributes.interaction_type !== 'string'
    ) {
        throw new Error(`metric ${metric.name} requires interaction_type`)
    }
    if (
        (metric.name === 'agent.session.cost_usd' ||
            metric.name === 'agent.interaction.cost_usd') &&
        attributes.cost_source !== 'estimated'
    ) {
        throw new Error(`metric ${metric.name} must use estimated cost`)
    }
}

export const recordWebMetricBatch = mutation({
    args: { metrics: v.array(webMetricInput) },
    handler: async (ctx, args): Promise<{ accepted: number }> => {
        if (args.metrics.length > 50) {
            throw new Error('metrics array max is 50')
        }
        const userId = await requireAuth(ctx)
        const metrics = args.metrics.map((metric) => {
            if (!Number.isFinite(metric.timestamp)) {
                throw new Error(
                    `metric ${metric.name} has an invalid timestamp`,
                )
            }
            if (
                metric.attributes &&
                Object.keys(metric.attributes).length > 32
            ) {
                throw new Error(`metric ${metric.name} has too many attributes`)
            }
            const normalized = normalizeMetric(metric, userId)
            assertWebMetric(normalized)
            return {
                ...normalized,
                source: 'web' as const,
                platform: 'web' as const,
                userId,
            }
        })
        return await insertMetricBatch(ctx, { receivedAt: Date.now(), metrics })
    },
})
