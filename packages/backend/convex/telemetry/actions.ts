import { v } from 'convex/values'
import { internal } from '../_generated/api'
import type { Doc } from '../_generated/dataModel'
import type { ActionCtx } from '../_generated/server'
import { internalAction } from '../_generated/server'
import { authComponent } from '../auth'
import type { MetricInput } from './types'

const defaultServiceName = 'walletbot-backend'
const exportBatchSize = 50
const maxErrorBodyLength = 512

type ReservedMetricExport = Doc<'telemetryMetrics'> & {
    cumulativeValue: number
    cumulativeStartTime: number
}
type ReservedMetricName = ReservedMetricExport['name']

const parseKeyValueList = (raw: string | undefined): Record<string, string> => {
    if (!raw) return {}
    const parsed: Record<string, string> = {}
    for (const part of raw.split(',')) {
        const [key, ...valueParts] = part.split('=')
        const trimmedKey = key?.trim()
        const value = valueParts.join('=').trim().replace(/%20/g, ' ')
        if (trimmedKey && value) parsed[trimmedKey] = value
    }
    return parsed
}

const parseHeaders = (raw: string | undefined): Record<string, string> =>
    parseKeyValueList(raw)

const resourceAttributes = (): Array<{
    key: string
    value: { stringValue: string }
}> => {
    const attributes = parseKeyValueList(process.env.OTEL_RESOURCE_ATTRIBUTES)
    attributes['service.name'] =
        attributes['service.name'] ??
        process.env.OTEL_SERVICE_NAME?.trim() ??
        defaultServiceName
    attributes['service.namespace'] =
        attributes['service.namespace'] ?? 'walletbot'
    const deploymentEnvironment =
        process.env.WALLETBOT_ENV?.trim() ||
        process.env.APP_ENV?.trim() ||
        process.env.NODE_ENV?.trim() ||
        process.env.CONVEX_DEPLOYMENT?.trim()
    if (deploymentEnvironment) {
        attributes['deployment.environment'] =
            attributes['deployment.environment'] ?? deploymentEnvironment
    }

    return Object.entries(attributes)
        .filter(([key, value]) => key.trim().length > 0 && value.length > 0)
        .map(([key, value]) => ({
            key,
            value: { stringValue: value },
        }))
}

const toAttributes = (
    event: Doc<'telemetryEvents'>,
): Array<{ key: string; value: { stringValue: string } }> => {
    const attributes: Array<{ key: string; value: { stringValue: string } }> = [
        { key: 'event.name', value: { stringValue: event.name } },
        {
            key: 'event.properties',
            value: { stringValue: JSON.stringify(event.properties) },
        },
    ]
    if (event.installationId) {
        attributes.push({
            key: 'installation.id',
            value: { stringValue: event.installationId },
        })
    }
    if (event.sessionId) {
        attributes.push({
            key: 'session.id',
            value: { stringValue: event.sessionId },
        })
    }
    if (event.userId) {
        attributes.push({
            key: 'user.id',
            value: { stringValue: event.userId },
        })
    }
    if (event.appVersion) {
        attributes.push({
            key: 'app.version',
            value: { stringValue: event.appVersion },
        })
    }
    if (event.platform) {
        attributes.push({
            key: 'app.platform',
            value: { stringValue: event.platform },
        })
    }
    return attributes
}

const toOtlpPayload = (events: Array<Doc<'telemetryEvents'>>) => {
    return {
        resourceLogs: [
            {
                resource: {
                    attributes: resourceAttributes(),
                },
                scopeLogs: [
                    {
                        scope: { name: 'walletbot.telemetry' },
                        logRecords: events.map((event) => ({
                            timeUnixNano: `${Math.trunc(event.timestamp * 1_000_000)}`,
                            observedTimeUnixNano: `${Math.trunc(
                                event.receivedAt * 1_000_000,
                            )}`,
                            severityText: 'INFO',
                            body: { stringValue: event.name },
                            attributes: toAttributes(event),
                        })),
                    },
                ],
            },
        ],
    }
}

const toOtlpMetricAttributes = (
    metric: ReservedMetricExport,
): Array<{
    key: string
    value: { stringValue?: string; doubleValue?: number; boolValue?: boolean }
}> => {
    const attributes: Array<{
        key: string
        value: {
            stringValue?: string
            doubleValue?: number
            boolValue?: boolean
        }
    }> = [{ key: 'metric.source', value: { stringValue: metric.source } }]

    const exportableKeys = exportableMetricAttributeKeys(metric.name)
    const metricAttributes = metric.attributes
    if (
        typeof metricAttributes === 'object' &&
        metricAttributes !== null &&
        !Array.isArray(metricAttributes)
    ) {
        for (const [key, value] of Object.entries(metricAttributes)) {
            if (!exportableKeys.has(key)) continue
            if (typeof value === 'string') {
                attributes.push({ key, value: { stringValue: value } })
            } else if (typeof value === 'number' && Number.isFinite(value)) {
                attributes.push({ key, value: { doubleValue: value } })
            } else if (typeof value === 'boolean') {
                attributes.push({ key, value: { boolValue: value } })
            }
        }
    }

    if (metric.appVersion) {
        attributes.push({
            key: 'app.version',
            value: { stringValue: metric.appVersion },
        })
    }
    if (metric.platform) {
        attributes.push({
            key: 'app.platform',
            value: { stringValue: metric.platform },
        })
    }
    return attributes
}

const exportableMetricAttributeKeys = (
    name: ReservedMetricName,
): Set<string> => {
    switch (name) {
        case 'business.financial_accounts.created_count':
        case 'business.movements.created_count':
            return new Set(['created_by', 'ingest_path'])
        case 'business.transfers.created_count':
            return new Set(['created_by', 'ingest_path', 'cross_currency'])
        case 'business.user_accounts.created_count':
            return new Set(['auth_method'])
        case 'business.user_accounts.signed_in_count':
            return new Set(['auth_method', 'client_platform'])
        case 'agent.sessions.started_count':
            return new Set(['model', 'start_kind'])
        case 'agent.session.cost_usd':
        case 'agent.interaction.cost_usd':
            return new Set([
                'model',
                'mode',
                'cost_source',
                'pricing_effective_from',
            ])
        case 'agent.user.monthly_cost_usd':
            return new Set(['user_hash', 'rank', 'month', 'model', 'mode'])
        case 'agent.interactions.completed_count':
            return new Set(['model', 'mode', 'interaction_type'])
        case 'agent.session.cost_bucket_count':
            return new Set(['model', 'mode', 'cost_bucket'])
        case 'agent.reports.submitted_count':
            return new Set(['reason', 'scope', 'client_platform'])
        case 'business.users.registered_total':
        case 'agent.session.cost_outlier_count':
            return new Set()
    }
}

const toOtlpMetricsPayload = (metrics: Array<ReservedMetricExport>) => {
    return {
        resourceMetrics: [
            {
                resource: {
                    attributes: resourceAttributes(),
                },
                scopeMetrics: [
                    {
                        scope: { name: 'walletbot.telemetry.metrics' },
                        metrics: metrics.map((metric) => {
                            const point = {
                                startTimeUnixNano: `${Math.trunc(metric.cumulativeStartTime * 1_000_000)}`,
                                timeUnixNano: `${Math.trunc(metric.receivedAt * 1_000_000)}`,
                                asDouble: metric.cumulativeValue,
                                attributes: toOtlpMetricAttributes(metric),
                            }
                            if (metric.type === 'gauge') {
                                return {
                                    name: metric.name,
                                    unit: metric.unit,
                                    gauge: { dataPoints: [point] },
                                }
                            }
                            return {
                                name: metric.name,
                                unit: metric.unit,
                                sum: {
                                    dataPoints: [point],
                                    aggregationTemporality: 2,
                                    isMonotonic: metric.value >= 0,
                                },
                            }
                        }),
                    },
                ],
            },
        ],
    }
}

const countRegisteredUsers = async (ctx: ActionCtx): Promise<number> => {
    const adapter = authComponent.adapter(ctx)({})
    return await adapter.count({ model: 'user' })
}

const recordRegisteredUsersTotalMetric = async (
    ctx: ActionCtx,
): Promise<{ count: number; accepted: number }> => {
    const count = await countRegisteredUsers(ctx)
    const result: { accepted: number } = await ctx.runMutation(
        internal.telemetry.mutations.insertMetricBatchMutation,
        {
            receivedAt: Date.now(),
            metrics: [
                {
                    name: 'business.users.registered_total',
                    timestamp: Date.now(),
                    source: 'backend',
                    type: 'gauge',
                    value: count,
                    unit: 'count',
                    attributes: {},
                },
            ],
        },
    )
    return { count, accepted: result.accepted }
}

const currentMonth = (): string => {
    const date = new Date()
    const month = `${date.getUTCMonth() + 1}`.padStart(2, '0')
    return `${date.getUTCFullYear()}-${month}`
}

const normalizeAgentMode = (mode: string): 'voice' | 'text' | 'mixed' => {
    if (mode === 'voice' || mode === 'text' || mode === 'mixed') return mode
    return 'mixed'
}

const userHash = async (userId: string): Promise<string> => {
    const input = new TextEncoder().encode(userId)
    const digest = await crypto.subtle.digest('SHA-256', input)
    return Array.from(new Uint8Array(digest))
        .slice(0, 12)
        .map((byte) => byte.toString(16).padStart(2, '0'))
        .join('')
}

const recordAgentMonthlyUsageMetric = async (
    ctx: ActionCtx,
    month = currentMonth(),
): Promise<{ rows: number; exportedRows: number; accepted: number }> => {
    const rows: Array<{
        userId: string
        month: string
        model: string
        mode: string
        estimatedCostUsd: number
    }> = await ctx.runQuery(
        internal.agentUsage.queries.listMonthlyUsageForTelemetry,
        { month },
    )

    if (rows.length === 0) return { rows: 0, exportedRows: 0, accepted: 0 }

    const now = Date.now()
    const topRows = rows
        .filter((row) => row.estimatedCostUsd > 0)
        .sort((a, b) => b.estimatedCostUsd - a.estimatedCostUsd)
        .slice(0, 20)
    const metrics: MetricInput[] = []
    for (const [index, row] of topRows.entries()) {
        const mode = normalizeAgentMode(row.mode)
        metrics.push({
            name: 'agent.user.monthly_cost_usd',
            timestamp: now,
            source: 'backend',
            type: 'gauge',
            value: row.estimatedCostUsd,
            unit: 'usd',
            userId: row.userId,
            attributes: {
                user_hash: await userHash(row.userId),
                rank: `${index + 1}`,
                month: row.month,
                model: row.model,
                mode,
            },
        })
    }
    if (metrics.length === 0) {
        return { rows: rows.length, exportedRows: 0, accepted: 0 }
    }
    const result: { accepted: number } = await ctx.runMutation(
        internal.telemetry.mutations.insertMetricBatchMutation,
        {
            receivedAt: now,
            metrics,
        },
    )
    return {
        rows: rows.length,
        exportedRows: metrics.length,
        accepted: result.accepted,
    }
}

export const recordRegisteredUsersTotal = internalAction({
    args: {},
    handler: async (ctx) => recordRegisteredUsersTotalMetric(ctx),
})

export const recordRegisteredUsersTotalNow = internalAction({
    args: {},
    handler: async (ctx) => recordRegisteredUsersTotalMetric(ctx),
})

export const recordAgentMonthlyUsage = internalAction({
    args: {},
    handler: async (ctx) => recordAgentMonthlyUsageMetric(ctx),
})

export const recordAgentMonthlyUsageNow = internalAction({
    args: { month: v.optional(v.string()) },
    handler: async (ctx, args) =>
        recordAgentMonthlyUsageMetric(ctx, args.month),
})

export const deleteDeprecatedAgentCostOutlierMetricsNow = internalAction({
    args: { limit: v.optional(v.number()) },
    handler: async (ctx, args): Promise<{ deleted: number }> => {
        return await ctx.runMutation(
            internal.telemetry.mutations
                .deleteDeprecatedAgentCostOutlierMetrics,
            { limit: args.limit ?? 100 },
        )
    },
})

const otlpSignalEndpoint = (
    signal: 'logs' | 'metrics',
    signalSpecificEndpoint: string | undefined,
): string | undefined => {
    const endpoint = signalSpecificEndpoint?.trim()
    if (endpoint) return endpoint

    const baseEndpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT?.trim()
    if (!baseEndpoint) return undefined

    const normalized = baseEndpoint.replace(/\/$/, '')
    if (normalized.endsWith(`/v1/${signal}`)) return normalized
    if (/\/v1\/(logs|metrics|traces)$/.test(normalized)) {
        return normalized.replace(
            /\/v1\/(logs|metrics|traces)$/,
            `/v1/${signal}`,
        )
    }
    return `${normalized}/v1/${signal}`
}

const otlpEndpoint = (): string | undefined => {
    return otlpSignalEndpoint(
        'logs',
        process.env.OTEL_EXPORTER_OTLP_LOGS_ENDPOINT,
    )
}

const otlpMetricsEndpoint = (): string | undefined => {
    return otlpSignalEndpoint(
        'metrics',
        process.env.OTEL_EXPORTER_OTLP_METRICS_ENDPOINT,
    )
}

const responseError = async (
    response: Response,
    args: { signal: 'logs' | 'metrics'; endpoint: string; batchSize: number },
): Promise<Error> => {
    const body = (await response.text()).slice(0, maxErrorBodyLength)
    const message = [
        `OTLP ${args.signal} export failed`,
        `status=${response.status}`,
        `endpoint=${args.endpoint}`,
        `batchSize=${args.batchSize}`,
        body ? `body=${body}` : undefined,
    ]
        .filter(Boolean)
        .join(' ')
    return new Error(message)
}

const logExportFailure = (args: {
    signal: 'logs' | 'metrics'
    endpoint?: string
    batchSize: number
    error: string
}): void => {
    console.warn('telemetry export failed', {
        signal: args.signal,
        endpoint: args.endpoint,
        batchSize: args.batchSize,
        error: args.error,
    })
}

export const exportPending = internalAction({
    args: {},
    handler: async (ctx) => {
        const events: Array<Doc<'telemetryEvents'>> = await ctx.runMutation(
            internal.telemetry.mutations.reserveEventExports,
            { limit: exportBatchSize },
        )
        if (events.length === 0) return { exported: 0 }

        const endpoint = otlpEndpoint()
        const ids = events.map((event) => event._id)
        if (!endpoint) {
            await ctx.runMutation(
                internal.telemetry.mutations.markExportFailed,
                {
                    ids,
                    error: 'OTEL_EXPORTER_OTLP_ENDPOINT not configured',
                },
            )
            return { exported: 0 }
        }

        try {
            const response = await fetch(endpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    ...parseHeaders(process.env.OTEL_EXPORTER_OTLP_HEADERS),
                },
                body: JSON.stringify(toOtlpPayload(events)),
            })
            if (!response.ok) {
                throw await responseError(response, {
                    signal: 'logs',
                    endpoint,
                    batchSize: events.length,
                })
            }
            await ctx.runMutation(internal.telemetry.mutations.markExported, {
                ids,
            })
            return { exported: events.length }
        } catch (err) {
            const message = err instanceof Error ? err.message : String(err)
            logExportFailure({
                signal: 'logs',
                endpoint,
                batchSize: events.length,
                error: message,
            })
            await ctx.runMutation(
                internal.telemetry.mutations.markExportFailed,
                {
                    ids,
                    error: message,
                },
            )
            return { exported: 0 }
        }
    },
})

export const exportPendingMetrics = internalAction({
    args: {},
    handler: async (ctx) => {
        const reservedMetrics: ReservedMetricExport[] = await ctx.runMutation(
            internal.telemetry.mutations.reserveMetricExports,
            { limit: exportBatchSize },
        )
        if (reservedMetrics.length === 0) return { exported: 0 }

        const endpoint = otlpMetricsEndpoint()
        if (!endpoint) {
            await ctx.runMutation(
                internal.telemetry.mutations.markMetricsExportFailed,
                {
                    ids: reservedMetrics.map((metric) => metric._id),
                    error: 'OTEL_EXPORTER_OTLP_ENDPOINT not configured',
                },
            )
            return { exported: 0 }
        }

        try {
            const response = await fetch(endpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    ...parseHeaders(process.env.OTEL_EXPORTER_OTLP_HEADERS),
                },
                body: JSON.stringify(toOtlpMetricsPayload(reservedMetrics)),
            })
            if (!response.ok) {
                throw await responseError(response, {
                    signal: 'metrics',
                    endpoint,
                    batchSize: reservedMetrics.length,
                })
            }
            await ctx.runMutation(
                internal.telemetry.mutations.markMetricsExported,
                { ids: reservedMetrics.map((metric) => metric._id) },
            )
            return { exported: reservedMetrics.length }
        } catch (err) {
            const message = err instanceof Error ? err.message : String(err)
            logExportFailure({
                signal: 'metrics',
                endpoint,
                batchSize: reservedMetrics.length,
                error: message,
            })
            await ctx.runMutation(
                internal.telemetry.mutations.markMetricsExportFailed,
                {
                    ids: reservedMetrics.map((metric) => metric._id),
                    error: message,
                },
            )
            return { exported: 0 }
        }
    },
})
