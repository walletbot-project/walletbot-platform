import { MediaModality, type UsageMetadata } from '@google/genai'
import type { ConvexReactClient } from 'convex/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import {
    AgentInteractionCostTracker,
    AgentSessionCostTracker,
    estimateSessionCostUsd,
    recordAgentSessionStarted,
    usageTokenAttributes,
} from '@/lib/agent-metrics'

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

describe('agent web metrics', () => {
    it('adds per-generation usage across reconnects instead of keeping only the last turn', () => {
        const tracker = new AgentSessionCostTracker()
        tracker.recordUsage({
            model: 'gemini-3.8-live',
            mode: 'voice',
            usage: {
                promptTokenCount: 100,
                responseTokenCount: 20,
                totalTokenCount: 120,
            },
        })
        // A new connection can report less usage than the preceding generation.
        tracker.recordUsage({
            model: 'gemini-3.8-live',
            mode: 'text',
            usage: {
                promptTokenCount: 30,
                responseTokenCount: 10,
                totalTokenCount: 40,
            },
        })
        expect(tracker.samples()).toEqual([
            {
                model: 'gemini-3.8-live',
                mode: 'mixed',
                costUsd: expect.closeTo(0.0002325, 10),
                tokenAttributes: {
                    token_input_text: 130,
                    token_output_text: 30,
                    token_total: 160,
                },
            },
        ])
    })

    it('keeps costs under the model that produced them when rollback changes the model', () => {
        const tracker = new AgentSessionCostTracker()
        for (const model of [
            'gemini-3.8-live',
            'gemini-3.1-flash-live-preview',
        ]) {
            tracker.recordUsage({
                model,
                mode: 'voice',
                usage: { totalTokenCount: 100 },
            })
        }
        expect(
            tracker.samples().map(({ model, tokenAttributes }) => ({
                model,
                tokenAttributes,
            })),
        ).toEqual([
            { model: 'gemini-3.8-live', tokenAttributes: { token_total: 100 } },
            {
                model: 'gemini-3.1-flash-live-preview',
                tokenAttributes: { token_total: 100 },
            },
        ])
        const empty = new AgentSessionCostTracker()
        empty.recordUsage({
            model: 'gemini-3.8-live',
            mode: 'voice',
            usage: {},
        })
        expect(empty.samples()).toEqual([])
    })

    it('records new and resumed session starts with native-compatible attributes', async () => {
        installBrowserGlobals()
        const mutation = vi.fn().mockResolvedValue({ accepted: 1 })
        const client = { mutation } as unknown as ConvexReactClient

        await recordAgentSessionStarted(client, {
            sessionId: 'session-new',
            model: 'gemini-live',
            resumed: false,
        })
        await recordAgentSessionStarted(client, {
            sessionId: 'session-resumed',
            model: 'gemini-live',
            resumed: true,
        })

        expect(mutation.mock.calls.map((call) => call[1].metrics[0])).toEqual([
            expect.objectContaining({
                name: 'agent.sessions.started_count',
                type: 'counter',
                value: 1,
                unit: 'count',
                sessionId: 'session-new',
                attributes: { model: 'gemini-live', start_kind: 'new' },
            }),
            expect.objectContaining({
                name: 'agent.sessions.started_count',
                type: 'counter',
                value: 1,
                unit: 'count',
                sessionId: 'session-resumed',
                attributes: { model: 'gemini-live', start_kind: 'resumed' },
            }),
        ])
    })

    it('estimates Gemini Live cost and token attributes from usage metadata', () => {
        const usage = {
            promptTokenCount: 1000,
            promptTokensDetails: [
                { modality: MediaModality.AUDIO, tokenCount: 100 },
                { modality: MediaModality.TEXT, tokenCount: 400 },
            ],
            responseTokenCount: 200,
            responseTokensDetails: [
                { modality: MediaModality.TEXT, tokenCount: 150 },
                { modality: MediaModality.AUDIO, tokenCount: 50 },
            ],
            totalTokenCount: 1200,
        } satisfies UsageMetadata

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

    it('ignores non-finite token counts', () => {
        expect(
            usageTokenAttributes({
                promptTokenCount: Number.NaN,
                responseTokenCount: 25,
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
