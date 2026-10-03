import type { MetricInput } from './types'

export type UsageActor = {
    actorType: 'user' | 'installation'
    actorKey: string
    userId?: string
}

// Native telemetry persists a UUID in secure storage. Also accept existing web
// installation keys, with a bounded format; none of these are credentials.
export const validInstallationId = (value: string): boolean =>
    /^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$/.test(value)

export const usageActor = async (
    metric: Pick<MetricInput, 'userId' | 'installationId'>,
): Promise<UsageActor | undefined> => {
    if (metric.userId) {
        return {
            actorType: 'user',
            actorKey: `user:${metric.userId}`,
            userId: metric.userId,
        }
    }
    if (!metric.installationId || !validInstallationId(metric.installationId)) {
        return undefined
    }
    const digest = await crypto.subtle.digest(
        'SHA-256',
        new TextEncoder().encode(`installation:${metric.installationId}`),
    )
    const hash = Array.from(new Uint8Array(digest))
        .map((byte) => byte.toString(16).padStart(2, '0'))
        .join('')
    return { actorType: 'installation', actorKey: `installation:${hash}` }
}
