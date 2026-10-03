import type { HttpRouter } from 'convex/server'
import { internal } from '../_generated/api'
import { httpAction } from '../_generated/server'
import { requireAuth } from '../users/helpers'
import {
    isObject,
    normalizeMetric,
    normalizeString,
    platforms,
} from './metricValidation'
import type {
    JsonValue,
    MetricInput,
    TelemetryEventInput,
    TelemetryPlatform,
} from './types'

const maxBatchSize = 50
const maxRequestBytes = 64 * 1024
const maxPropertiesBytes = 8 * 1024
const maxNameLength = 120
const maxStringLength = 2048
const maxArrayLength = 64
const maxObjectKeys = 64
const maxJsonDepth = 8

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
