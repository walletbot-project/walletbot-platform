/**
 * Best-effort metric client for the backend's `POST /telemetry/metrics`
 * endpoint (`packages/backend/convex/telemetry/http.ts`). Web counterpart of
 * native's `TelemetryClient` (`apps/native/lib/telemetry/telemetry_client.dart`):
 * one metric per request, an optional bearer token, and an installation id
 * that survives reloads so anonymous metrics are still attributable.
 *
 * Nothing here ever throws or is awaited by a caller — telemetry must not cost
 * the user anything. Failures are only logged with `console.warn`.
 */

/**
 * Bucket labels for client-observed latency. Same boundaries as native's
 * `clientDurationBucket` (`apps/native/lib/telemetry/duration_bucket.dart`)
 * and the backend catalog's `CLIENT_DURATION_BUCKETS`.
 */
export type ClientDurationBucket =
    | '0-250'
    | '250-500'
    | '500-1000'
    | '1000-2500'
    | '2500-5000'
    | '5000+'

export function clientDurationBucket(elapsedMs: number): ClientDurationBucket {
    if (elapsedMs < 250) return '0-250'
    if (elapsedMs < 500) return '250-500'
    if (elapsedMs < 1000) return '500-1000'
    if (elapsedMs < 2500) return '1000-2500'
    if (elapsedMs < 5000) return '2500-5000'
    return '5000+'
}

/**
 * The metrics web emits, with the type, unit and attributes the backend
 * catalog (`packages/backend/convex/telemetry/catalog.ts`) requires for each.
 * The endpoint rejects anything else, so it is typed here rather than checked
 * at runtime.
 */
type MetricSpecs = {
    'voice.connect.setup_complete_bucket_count': {
        type: 'counter'
        unit: 'count'
        attributes: {
            bucket: ClientDurationBucket
            platform: 'web'
            resumed: boolean
        }
    }
    'agent.response.first_token_ms': {
        type: 'gauge'
        unit: 'ms'
        attributes: { mode: 'text' | 'voice'; platform: 'web' }
    }
}

export type WebMetricName = keyof MetricSpecs

export type WebMetric = {
    [Name in WebMetricName]: { name: Name; value: number } & MetricSpecs[Name]
}[WebMetricName]

export type TelemetryClient = {
    /** One per page load. */
    readonly sessionId: string
    /** Fire and forget: never throws, never needs awaiting. */
    trackMetric: (metric: WebMetric) => void
}

export type TelemetryClientOptions = {
    /** The Convex site URL (`VITE_CONVEX_SITE_URL`). Empty disables sending. */
    siteUrl: string | undefined
    appVersion?: string
    /**
     * A Convex JWT, or null to send anonymously. The endpoint answers 401 to an
     * invalid `Authorization` header, so it is only sent when a token exists.
     */
    getAccessToken?: () => Promise<string | null>
    fetch?: typeof fetch
    /** A getter, because touching `localStorage` itself can throw. */
    storage?: () => Storage
    newId?: () => string
    now?: () => number
}

/** Same key native uses in its secure storage. */
export const INSTALLATION_ID_KEY = 'telemetry_installation_id'

export function createTelemetryClient(
    options: TelemetryClientOptions,
): TelemetryClient {
    const newId = options.newId ?? (() => crypto.randomUUID())
    const now = options.now ?? Date.now
    const storage = options.storage ?? (() => localStorage)
    const sessionId = newId()
    let installationId: string | undefined

    const readInstallationId = (): string => {
        if (installationId) return installationId
        try {
            const existing = storage().getItem(INSTALLATION_ID_KEY)
            if (existing) {
                installationId = existing
                return existing
            }
        } catch {
            // Restricted storage (private mode, blocked site data).
        }
        const created = newId()
        // Kept in memory either way, so one page load keeps one id even
        // when it cannot be persisted.
        installationId = created
        try {
            storage().setItem(INSTALLATION_ID_KEY, created)
        } catch {
            // Same as above: the in-memory id still serves this page load.
        }
        return created
    }

    const readAccessToken = async (): Promise<string | null> => {
        if (!options.getAccessToken) return null
        try {
            return await options.getAccessToken()
        } catch (error) {
            console.warn('telemetry: access token unavailable', error)
            return null
        }
    }

    const send = async (metric: WebMetric): Promise<void> => {
        const siteUrl = options.siteUrl
        if (!siteUrl) return
        try {
            const token = await readAccessToken()
            const headers: Record<string, string> = {
                'Content-Type': 'application/json',
            }
            if (token) headers.Authorization = `Bearer ${token}`
            const response = await (options.fetch ?? fetch)(
                `${siteUrl}/telemetry/metrics`,
                {
                    method: 'POST',
                    keepalive: true,
                    headers,
                    body: JSON.stringify({
                        metrics: [
                            {
                                name: metric.name,
                                timestamp: now(),
                                source: 'web',
                                type: metric.type,
                                value: metric.value,
                                unit: metric.unit,
                                attributes: metric.attributes,
                                installationId: readInstallationId(),
                                sessionId,
                                ...(options.appVersion
                                    ? { appVersion: options.appVersion }
                                    : {}),
                                platform: 'web',
                            },
                        ],
                    }),
                },
            )
            if (!response.ok) {
                const body = await response.text().catch(() => '')
                console.warn(
                    `telemetry metrics: HTTP ${response.status}: ${body}`,
                )
            }
        } catch (error) {
            console.warn('telemetry metrics: send failed', error)
        }
    }

    return {
        sessionId,
        trackMetric: (metric) => {
            void send(metric)
        },
    }
}
