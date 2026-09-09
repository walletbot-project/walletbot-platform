import { describe, expect, it } from 'vitest'
import {
    AgentInteractionCostTracker,
    estimateSessionCostUsd,
    usageTokenAttributes,
} from '@/lib/agent-metrics'

describe('agent web metrics', () => {
    it('estimates Gemini Live cost and token attributes from usage metadata', () => {
        const usage = {
            promptTokenCount: 1000,
            promptTokensDetails: [
                { modality: 'audio', tokenCount: 100 },
                { modality: 'text', tokenCount: 400 },
            ],
            responseTokenCount: 200,
            responseTokensDetails: [
                { modality: 'TEXT', tokenCount: 150 },
                { modalityType: 'audio', tokenCount: 50 },
            ],
            totalTokenCount: 1200,
        }

        expect(estimateSessionCostUsd(usage)).toBeCloseTo(0.00225)
        expect(usageTokenAttributes(usage)).toEqual({
            token_input_audio: 100,
            token_input_text: 900,
            token_output_text: 150,
            token_output_audio: 50,
            token_total: 1200,
        })
    })

    it('uses the native text-output fallback for total token count only', () => {
        expect(estimateSessionCostUsd({ totalTokenCount: 1000 })).toBeCloseTo(
            0.0045,
        )
        expect(usageTokenAttributes({ totalTokenCount: 1000 })).toEqual({
            token_total: 1000,
        })
    })

    it('matches native integer parsing for malformed numeric strings', () => {
        expect(
            usageTokenAttributes({
                promptTokenCount: '100invalid',
                responseTokenCount: '25',
            }),
        ).toEqual({ token_output_text: 25 })
    })

    it('converts cumulative totals to interaction deltas', () => {
        let next = 0
        const tracker = new AgentInteractionCostTracker(() => `id-${++next}`)

        const first = tracker.nextSample({
            sessionId: 'session-1',
            totalCostUsd: 0.1,
            fallbackInteractionType: 'voice',
            tokenAttributes: { token_input_text: 100 },
        })
        const second = tracker.nextSample({
            sessionId: 'session-1',
            totalCostUsd: 0.25,
            fallbackInteractionType: 'voice',
            tokenAttributes: { token_input_text: 250 },
        })

        expect(first).toMatchObject({
            costUsd: 0.1,
            tokenAttributes: { token_input_text: 100 },
        })
        expect(second?.costUsd).toBeCloseTo(0.15)
        expect(second?.tokenAttributes).toEqual({ token_input_text: 150 })
    })

    it('does not emit duplicate unchanged totals', () => {
        const tracker = new AgentInteractionCostTracker(() => 'id-1')
        const sample = {
            sessionId: 'session-1',
            totalCostUsd: 0.1,
            fallbackInteractionType: 'text' as const,
            tokenAttributes: { token_input_text: 100 },
        }

        expect(tracker.nextSample(sample)).not.toBeNull()
        expect(tracker.nextSample(sample)).toBeNull()
    })

    it('uses unique sample ids for the same session', () => {
        let next = 0
        const tracker = new AgentInteractionCostTracker(() => `id-${++next}`)

        const first = tracker.nextSample({
            sessionId: 'session-1',
            totalCostUsd: 0.1,
            fallbackInteractionType: 'text',
            tokenAttributes: { token_input_text: 100 },
        })
        const second = tracker.nextSample({
            sessionId: 'session-1',
            totalCostUsd: 0.2,
            fallbackInteractionType: 'text',
            tokenAttributes: { token_input_text: 200 },
        })

        expect(first?.sampleId).toBe('session-1:id-1')
        expect(second?.sampleId).toBe('session-1:id-2')
    })

    it('consumes a tool marker even when no sample is emitted', () => {
        const tracker = new AgentInteractionCostTracker(() => 'id')
        const first = {
            sessionId: 'session-1',
            totalCostUsd: 0.1,
            fallbackInteractionType: 'voice' as const,
            tokenAttributes: { token_input_text: 100 },
        }

        tracker.markToolCall()
        tracker.nextSample(first)
        tracker.markToolCall()
        expect(tracker.nextSample(first)).toBeNull()

        expect(
            tracker.nextSample({
                ...first,
                totalCostUsd: 0.2,
                tokenAttributes: { token_input_text: 200 },
            })?.interactionType,
        ).toBe('voice')
    })

    it('marks a changed sample as a tool interaction', () => {
        const tracker = new AgentInteractionCostTracker(() => 'id-1')
        tracker.markToolCall()

        expect(
            tracker.nextSample({
                sessionId: 'session-1',
                totalCostUsd: 0.1,
                fallbackInteractionType: 'text',
                tokenAttributes: { token_input_text: 100 },
            })?.interactionType,
        ).toBe('tool')
    })
})
