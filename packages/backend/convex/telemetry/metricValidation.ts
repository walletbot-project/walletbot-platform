import {
    metricCatalog,
    metricNames,
    metricSources,
    metricTypes,
    metricUnits,
} from './catalog'
import type {
    MetricAttributeValue,
    MetricInput,
    MetricName,
    MetricSource,
    MetricType,
    MetricUnit,
    TelemetryPlatform,
} from './types'

const maxAttributesBytes = 4 * 1024
const maxAttributeStringLength = 256
const maxAttributeKeys = 32

export const platforms = new Set<TelemetryPlatform>([
    'ios',
    'android',
    'web',
    'macos',
    'windows',
    'linux',
])

export const isObject = (value: unknown): value is Record<string, unknown> =>
    typeof value === 'object' && value !== null && !Array.isArray(value)

export const normalizeString = (value: unknown): string | undefined => {
    if (typeof value !== 'string') return undefined
    const trimmed = value.trim()
    return trimmed.length > 0 ? trimmed : undefined
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

export const normalizeMetric = (
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
