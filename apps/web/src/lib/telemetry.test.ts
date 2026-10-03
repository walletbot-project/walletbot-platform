import type { ConvexReactClient } from 'convex/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { recordWebMetricBatch } from '@/lib/telemetry'

const metric = {
    name: 'agent.session.cost_usd' as const,
    type: 'gauge' as const,
    value: 0.01,
    unit: 'usd' as const,
    attributes: { model: 'gemini-3.1-flash-live-preview' },
    sessionId: 'session-1',
}

const installBrowserGlobals = () => {
    const values = new Map<string, string>()
    vi.stubGlobal('localStorage', {
        getItem: (key: string) => values.get(key) ?? null,
        setItem: (key: string, value: string) => values.set(key, value),
    })
    vi.stubGlobal('crypto', { randomUUID: () => 'installation-1' })
}

afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
})

describe('web telemetry client', () => {
    it('adds the web envelope and reuses a stable installation id', async () => {
        installBrowserGlobals()
        const mutation = vi.fn().mockResolvedValue({ accepted: 1 })
        const client = { mutation } as unknown as ConvexReactClient

        await recordWebMetricBatch(client, [metric])
        await recordWebMetricBatch(client, [metric])

        expect(mutation).toHaveBeenCalledTimes(2)
        for (const call of mutation.mock.calls) {
            expect(call[1]).toMatchObject({
                metrics: [
                    {
                        ...metric,
                        source: 'web',
                        platform: 'web',
                        appVersion: '0.5.1',
                        installationId: 'installation-1',
                    },
                ],
            })
        }
    })

    it('absorbs mutation failures', async () => {
        installBrowserGlobals()
        const error = new Error('offline')
        const mutation = vi.fn().mockRejectedValue(error)
        const client = { mutation } as unknown as ConvexReactClient
        const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})

        await expect(recordWebMetricBatch(client, [metric])).resolves.toBe(
            undefined,
        )
        expect(warn).toHaveBeenCalledWith(
            'telemetry metrics: send failed',
            error,
        )
    })
})
