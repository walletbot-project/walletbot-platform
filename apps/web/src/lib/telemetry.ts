import { api } from '@wallet-bot/backend/api'
import type { ConvexReactClient } from 'convex/react'

type MetricType = 'counter' | 'gauge' | 'histogram'
type MetricUnit = 'count' | 'ms' | 'usd'
type MetricAttributeValue = string | number | boolean
type WebMetricName =
    | 'agent.session.cost_usd'
    | 'agent.interaction.cost_usd'
    | 'agent.interactions.completed_count'

export type TelemetryMetric = {
    name: WebMetricName
    timestamp?: number
    type: MetricType
    value: number
    unit?: MetricUnit
    attributes?: Record<string, MetricAttributeValue>
    sessionId?: string
    sampleId?: string
}

const installationIdKey = 'telemetry_installation_id'
const appVersion = '0.0.0'

const installationId = (): string => {
    const existing = localStorage.getItem(installationIdKey)
    if (existing) return existing
    const created = crypto.randomUUID()
    localStorage.setItem(installationIdKey, created)
    return created
}

export const recordWebMetricBatch = async (
    client: ConvexReactClient,
    metrics: readonly TelemetryMetric[],
): Promise<void> => {
    if (metrics.length === 0) return

    try {
        await client.mutation(api.telemetry.mutations.recordWebMetricBatch, {
            metrics: metrics.map((metric) => ({
                name: metric.name,
                timestamp: metric.timestamp ?? Date.now(),
                source: 'web' as const,
                type: metric.type,
                value: metric.value,
                unit: metric.unit,
                attributes: metric.attributes ?? {},
                installationId: installationId(),
                sessionId: metric.sessionId,
                sampleId: metric.sampleId,
                appVersion,
                platform: 'web' as const,
            })),
        })
    } catch (error) {
        console.warn('telemetry metrics: send failed', error)
    }
}
