import { describe, expect, it } from 'vitest'
import { normalizeMetric } from '../convex/telemetry/metricValidation'

const webSessionMetric = {
    name: 'agent.sessions.started_count',
    timestamp: 1_000,
    source: 'web',
    type: 'counter',
    value: 1,
    unit: 'count',
    sessionId: 'session-1',
    attributes: { model: ' gemini-3.1-flash-live-preview ', start_kind: 'new' },
}

describe('shared metric validation', () => {
    it('normalizes allowed attributes for HTTP and Convex client metrics', () => {
        expect(normalizeMetric(webSessionMetric, 'user-1')).toMatchObject({
            userId: 'user-1',
            attributes: {
                model: 'gemini-3.1-flash-live-preview',
                start_kind: 'new',
            },
        })
    })

    it('rejects attributes outside the catalog', () => {
        expect(() =>
            normalizeMetric(
                {
                    ...webSessionMetric,
                    attributes: { model: 'gemini', start_kind: 'bogus' },
                },
                'user-1',
            ),
        ).toThrow('unsupported value')
    })
})
