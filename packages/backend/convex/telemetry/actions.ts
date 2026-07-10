import { internal } from '../_generated/api'
import type { Doc } from '../_generated/dataModel'
import { internalAction } from '../_generated/server'

const defaultServiceName = 'walletbot-backend'
const exportBatchSize = 50

const parseHeaders = (raw: string | undefined): Record<string, string> => {
    if (!raw) return {}
    const parsed: Record<string, string> = {}
    for (const part of raw.split(',')) {
        const [key, ...valueParts] = part.split('=')
        const trimmedKey = key?.trim()
        const value = valueParts.join('=').trim()
        if (trimmedKey && value) parsed[trimmedKey] = value
    }
    return parsed
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
    const serviceName = process.env.OTEL_SERVICE_NAME ?? defaultServiceName
    return {
        resourceLogs: [
            {
                resource: {
                    attributes: [
                        {
                            key: 'service.name',
                            value: { stringValue: serviceName },
                        },
                    ],
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

const otlpEndpoint = (): string | undefined => {
    const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT?.trim()
    if (!endpoint) return undefined
    return endpoint.endsWith('/v1/logs') ? endpoint : `${endpoint}/v1/logs`
}

export const exportPending = internalAction({
    args: {},
    handler: async (ctx) => {
        const events: Array<Doc<'telemetryEvents'>> = await ctx.runQuery(
            internal.telemetry.queries.pendingForExport,
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
                throw new Error(`OTLP export failed with ${response.status}`)
            }
            await ctx.runMutation(internal.telemetry.mutations.markExported, {
                ids,
            })
            return { exported: events.length }
        } catch (err) {
            const message = err instanceof Error ? err.message : String(err)
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
