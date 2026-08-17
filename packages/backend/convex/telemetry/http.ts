import type { HttpRouter } from 'convex/server'
import { internal } from '../_generated/api'
import { httpAction } from '../_generated/server'
import { requireAuth } from '../users/helpers'
import {
    metricCatalog,
    metricNames,
    metricSources,
    metricTypes,
    metricUnits,
} from './catalog'
import type {
    JsonValue,
    MetricAttributeValue,
    MetricInput,
    MetricName,
    MetricSource,
    MetricType,
    MetricUnit,
    TelemetryEventInput,
    TelemetryPlatform,
} from './types'

const maxBatchSize = 50
const maxRequestBytes = 64 * 1024
const maxPropertiesBytes = 8 * 1024
const maxAttributesBytes = 4 * 1024
const maxNameLength = 120
const maxStringLength = 2048
const maxAttributeStringLength = 256
const maxAttributeKeys = 32
const maxArrayLength = 64
const maxObjectKeys = 64
const maxJsonDepth = 8

const platforms = new Set<TelemetryPlatform>([
    'ios',
    'android',
    'web',
    'macos',
    'windows',
    'linux',
])

const jsonResponse = (body: unknown, init?: ResponseInit): Response => {
    const headers = new Headers(init?.headers)
    if (!headers.has('Content-Type')) {
        headers.set('Content-Type', 'application/json')
    }
    headers.set('Access-Control-Allow-Origin', '*')
    headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization')
    headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS')
    return new Response(JSON.stringify(body), { ...init, headers })
}

const jsonError = (status: number, code: string, message: string): Response =>
    jsonResponse({ code, message }, { status })

const corsHeaders = (): Headers => {
    const headers = new Headers()
    headers.set('Access-Control-Allow-Origin', '*')
    headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization')
    headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS')
    return headers
}

const corsPreflightHandler = httpAction(async () => {
    return new Response(null, { status: 204, headers: corsHeaders() })
})

const isObject = (value: unknown): value is Record<string, unknown> =>
    typeof value === 'object' && value !== null && !Array.isArray(value)

const normalizeString = (value: unknown): string | undefined => {
    if (typeof value !== 'string') return undefined
    const trimmed = value.trim()
    return trimmed.length > 0 ? trimmed : undefined
}

const normalizeJson = (value: unknown, depth = 0): JsonValue => {
    if (depth > maxJsonDepth) {
        throw new Error('properties depth limit exceeded')
    }
    if (value === null) return null
    if (typeof value === 'boolean') return value
    if (typeof value === 'number') {
        if (!Number.isFinite(value)) throw new Error('invalid number')
        return value
    }
    if (typeof value === 'string') return value.slice(0, maxStringLength)
    if (Array.isArray(value)) {
        return value
            .slice(0, maxArrayLength)
            .map((item) => normalizeJson(item, depth + 1))
    }
    if (!isObject(value)) {
        throw new Error('unsupported properties value')
    }

    const entries = Object.entries(value).slice(0, maxObjectKeys)
    const normalized: { [key: string]: JsonValue } = {}
    for (const [key, entryValue] of entries) {
        const cleanKey = key.trim()
        if (
            cleanKey.length === 0 ||
            cleanKey.startsWith('$') ||
            cleanKey.startsWith('_')
        ) {
            continue
        }
        normalized[cleanKey.slice(0, 128)] = normalizeJson(
            entryValue,
            depth + 1,
        )
    }
    return normalized
}

const normalizeProperties = (value: unknown): JsonValue => {
    const normalized = normalizeJson(value ?? {})
    const encoded = JSON.stringify(normalized)
    if (encoded.length > maxPropertiesBytes) {
        throw new Error('properties too large')
    }
    return normalized
}

const normalizeMetricAttributes = (
    name: MetricName,
    value: unknown,
): Record<string, MetricAttributeValue> | undefined => {
    if (value === undefined) return undefined
    if (!isObject(value)) throw new Error('attributes must be an object')

    const catalog = metricCatalog[name].attributes
    const normalized: Record<string, MetricAttributeValue> = {}
    for (const [key, rawValue] of Object.entries(value).slice(
        0,
        maxAttributeKeys,
    )) {
        const cleanKey = key.trim()
        if (!Object.hasOwn(catalog, cleanKey)) {
            throw new Error(`attribute ${cleanKey} is not allowed for ${name}`)
        }
        let cleanValue: MetricAttributeValue
        if (typeof rawValue === 'string') {
            const trimmed = rawValue.trim()
            if (!trimmed) throw new Error(`attribute ${cleanKey} is empty`)
            cleanValue = trimmed.slice(0, maxAttributeStringLength)
        } else if (typeof rawValue === 'number') {
            if (!Number.isFinite(rawValue)) {
                throw new Error(`attribute ${cleanKey} is not finite`)
            }
            cleanValue = rawValue
        } else if (typeof rawValue === 'boolean') {
            cleanValue = rawValue
        } else {
            throw new Error(`attribute ${cleanKey} has invalid value`)
        }

        const allowed = catalog[cleanKey]
        if (allowed !== 'string' && !allowed.has(cleanValue)) {
            throw new Error(`attribute ${cleanKey} has unsupported value`)
        }
        normalized[cleanKey] = cleanValue
    }

    const encoded = JSON.stringify(normalized)
    if (encoded.length > maxAttributesBytes) {
        throw new Error('attributes too large')
    }
    return normalized
}

const normalizeEvent = (
    value: unknown,
    userId: string | undefined,
): TelemetryEventInput => {
    if (!isObject(value)) throw new Error('event must be an object')

    const name = normalizeString(value.name)
    if (!name || name.length > maxNameLength) {
        throw new Error('event name is invalid')
    }

    const timestamp =
        typeof value.timestamp === 'number' && Number.isFinite(value.timestamp)
            ? value.timestamp
            : Date.now()
    const installationId = normalizeString(value.installationId)
    if (!userId && !installationId) {
        throw new Error('anonymous events require installationId')
    }

    const platform =
        typeof value.platform === 'string' &&
        platforms.has(value.platform as TelemetryPlatform)
            ? (value.platform as TelemetryPlatform)
            : undefined

    return {
        name,
        timestamp,
        properties: normalizeProperties(value.properties),
        ...(installationId ? { installationId } : {}),
        ...(normalizeString(value.sessionId)
            ? { sessionId: normalizeString(value.sessionId) }
            : {}),
        ...(normalizeString(value.sampleId)
            ? { sampleId: normalizeString(value.sampleId) }
            : {}),
        ...(userId ? { userId } : {}),
        ...(normalizeString(value.appVersion)
            ? { appVersion: normalizeString(value.appVersion) }
            : {}),
        ...(platform ? { platform } : {}),
    }
}

const parseEvents = (
    body: unknown,
    userId: string | undefined,
): TelemetryEventInput[] => {
    if (!isObject(body) || !Array.isArray(body.events)) {
        throw new Error('missing events array')
    }
    if (body.events.length === 0) {
        throw new Error('events array must not be empty')
    }
    if (body.events.length > maxBatchSize) {
        throw new Error(`events array max is ${maxBatchSize}`)
    }
    return body.events.map((event) => normalizeEvent(event, userId))
}

const normalizeMetric = (
    value: unknown,
    userId: string | undefined,
): MetricInput => {
    if (!isObject(value)) throw new Error('metric must be an object')

    const rawName = normalizeString(value.name)
    if (!rawName || !metricNames.has(rawName as MetricName)) {
        throw new Error('metric name is not in catalog')
    }
    const name = rawName as MetricName
    const catalog = metricCatalog[name]

    const timestamp =
        typeof value.timestamp === 'number' && Number.isFinite(value.timestamp)
            ? value.timestamp
            : Date.now()

    const rawSource = normalizeString(value.source)
    if (!rawSource || !metricSources.has(rawSource as MetricSource)) {
        throw new Error('metric source is invalid')
    }
    const source = rawSource as MetricSource

    const rawType = normalizeString(value.type)
    if (!rawType || !metricTypes.has(rawType as MetricType)) {
        throw new Error('metric type is invalid')
    }
    const type = rawType as MetricType
    if (type !== catalog.type) {
        throw new Error(`metric ${name} must be type ${catalog.type}`)
    }

    if (typeof value.value !== 'number' || !Number.isFinite(value.value)) {
        throw new Error('metric value is invalid')
    }
    if (type === 'counter' && value.value < 0) {
        throw new Error('counter metric value must be non-negative')
    }

    const rawUnit = normalizeString(value.unit)
    const unit = rawUnit ? (rawUnit as MetricUnit) : catalog.unit
    if (!metricUnits.has(unit)) {
        throw new Error('metric unit is invalid')
    }
    if (unit !== catalog.unit) {
        throw new Error(`metric ${name} must use unit ${catalog.unit}`)
    }

    const installationId = normalizeString(value.installationId)
    if (!userId && !installationId) {
        throw new Error('anonymous metrics require installationId')
    }

    const platform =
        typeof value.platform === 'string' &&
        platforms.has(value.platform as TelemetryPlatform)
            ? (value.platform as TelemetryPlatform)
            : undefined

    return {
        name,
        timestamp,
        source,
        type,
        value: value.value,
        unit,
        attributes: normalizeMetricAttributes(name, value.attributes),
        ...(installationId ? { installationId } : {}),
        ...(normalizeString(value.sessionId)
            ? { sessionId: normalizeString(value.sessionId) }
            : {}),
        ...(userId ? { userId } : {}),
        ...(normalizeString(value.appVersion)
            ? { appVersion: normalizeString(value.appVersion) }
            : {}),
        ...(platform ? { platform } : {}),
    }
}

const parseMetrics = (
    body: unknown,
    userId: string | undefined,
): MetricInput[] => {
    if (!isObject(body) || !Array.isArray(body.metrics)) {
        throw new Error('missing metrics array')
    }
    if (body.metrics.length === 0) {
        throw new Error('metrics array must not be empty')
    }
    if (body.metrics.length > maxBatchSize) {
        throw new Error(`metrics array max is ${maxBatchSize}`)
    }
    return body.metrics.map((metric) => normalizeMetric(metric, userId))
}

const telemetryEventsHandler = httpAction(async (ctx, req) => {
    const raw = await req.text()
    if (raw.length > maxRequestBytes) {
        return jsonError(413, 'payload_too_large', 'payload too large')
    }

    let body: unknown
    try {
        body = JSON.parse(raw)
    } catch {
        return jsonError(400, 'bad_json', 'invalid JSON body')
    }

    let userId: string | undefined
    if (req.headers.get('authorization')) {
        try {
            userId = await requireAuth(ctx)
        } catch {
            return jsonError(401, 'unauthenticated', 'invalid access token')
        }
    }

    let events: TelemetryEventInput[]
    try {
        events = parseEvents(body, userId)
    } catch (err) {
        const message = err instanceof Error ? err.message : 'invalid payload'
        return jsonError(400, 'bad_request', message)
    }

    const result: { accepted: number } = await ctx.runMutation(
        internal.telemetry.mutations.insertBatch,
        {
            events,
            receivedAt: Date.now(),
        },
    )

    return jsonResponse({ ok: true, accepted: result.accepted })
})

const telemetryMetricsHandler = httpAction(async (ctx, req) => {
    const raw = await req.text()
    if (raw.length > maxRequestBytes) {
        return jsonError(413, 'payload_too_large', 'payload too large')
    }

    let body: unknown
    try {
        body = JSON.parse(raw)
    } catch {
        return jsonError(400, 'bad_json', 'invalid JSON body')
    }

    let userId: string | undefined
    if (req.headers.get('authorization')) {
        try {
            userId = await requireAuth(ctx)
        } catch {
            return jsonError(401, 'unauthenticated', 'invalid access token')
        }
    }

    let metrics: MetricInput[]
    try {
        metrics = parseMetrics(body, userId)
    } catch (err) {
        const message = err instanceof Error ? err.message : 'invalid payload'
        return jsonError(400, 'bad_request', message)
    }

    const result: { accepted: number } = await ctx.runMutation(
        internal.telemetry.mutations.insertMetricBatchMutation,
        {
            metrics,
            receivedAt: Date.now(),
        },
    )

    return jsonResponse({ ok: true, accepted: result.accepted })
})

export const registerTelemetryRoutes = (http: HttpRouter): void => {
    http.route({
        path: '/telemetry/events',
        method: 'OPTIONS',
        handler: corsPreflightHandler,
    })
    http.route({
        path: '/telemetry/events',
        method: 'POST',
        handler: telemetryEventsHandler,
    })
    http.route({
        path: '/telemetry/metrics',
        method: 'OPTIONS',
        handler: corsPreflightHandler,
    })
    http.route({
        path: '/telemetry/metrics',
        method: 'POST',
        handler: telemetryMetricsHandler,
    })
}
