const installationIdKey = 'telemetry_installation_id'

const installationId = () => {
    const existing = localStorage.getItem(installationIdKey)
    if (existing) return existing
    const created =
        globalThis.crypto?.randomUUID?.() ??
        `${Date.now()}-${Math.random().toString(16).slice(2)}`
    localStorage.setItem(installationIdKey, created)
    return created
}

export const trackMetric = async (
    name: string,
    {
        type,
        value,
        unit,
        attributes = {},
    }: {
        type: 'counter' | 'gauge' | 'histogram'
        value: number
        unit?: 'count' | 'ms' | 'usd'
        attributes?: Record<string, string | number | boolean>
    },
) => {
    const baseUrl = import.meta.env.VITE_CONVEX_SITE_URL
    if (!baseUrl) return

    try {
        await fetch(`${baseUrl}/telemetry/metrics`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                metrics: [
                    {
                        name,
                        timestamp: Date.now(),
                        source: 'web',
                        type,
                        value,
                        unit,
                        attributes,
                        installationId: installationId(),
                        platform: 'web',
                    },
                ],
            }),
        })
    } catch {
        // Telemetry is best-effort and must not block auth navigation.
    }
}
