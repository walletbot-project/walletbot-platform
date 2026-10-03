import { expect, it } from 'vitest'
import { normalizeAgentCostMetric } from '../convex/telemetry/agentPricing'
import { webVoiceMetric } from '../convex/v1/voice/metrics'

const metric = (model: string, id: string, responseTokens: number) =>
    webVoiceMetric({
        userId: 'user',
        sessionId: 'session',
        event: {
            id,
            type: 'usage_metadata',
            occurredAt: BigInt(Date.parse('2026-09-21T00:00:00Z')),
            payloadJson: JSON.stringify({
                model,
                mode: 'audio',
                promptTokenCount: 1000,
                responseTokenCount: responseTokens,
                responseTokensDetails: [
                    { modality: 'AUDIO', tokenCount: responseTokens },
                ],
            }),
        },
    })!
it('prices equal and smaller turns in full, without subtracting earlier generations', () => {
    for (const model of ['gemini-3.8-live', 'gemini-3.1-flash-live-preview']) {
        const first = normalizeAgentCostMetric(metric(model, 'a', 1000))!
        const equal = normalizeAgentCostMetric(metric(model, 'b', 1000))!
        const smaller = normalizeAgentCostMetric(metric(model, 'c', 500))!
        expect(first.value).toBeCloseTo(0.01275)
        expect(equal.value).toBe(first.value)
        expect(smaller.value).toBeCloseTo(0.00675)
        expect(smaller.attributes?.model).toBe(model)
        expect(equal.sampleId).not.toBe(first.sampleId)
    }
})
it('counts completion from turnComplete, not usage notifications', () => {
    const event = {
        id: 'turn',
        type: 'agent_turn_complete',
        occurredAt: 1n,
        payloadJson: JSON.stringify({ model: 'gemini-3.8-live', mode: 'text' }),
    }
    expect(
        webVoiceMetric({ userId: 'user', sessionId: 'session', event }),
    ).toMatchObject({
        name: 'agent.interactions.completed_count',
        value: 1,
        attributes: { model: 'gemini-3.8-live', mode: 'text' },
    })
    expect(
        webVoiceMetric({
            userId: 'user',
            sessionId: 'session',
            event: { ...event, payloadJson: '{}' },
        }),
    ).toBeNull()
})
