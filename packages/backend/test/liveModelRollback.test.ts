import { afterEach, describe, expect, it, vi } from 'vitest'
import { KNOWN_FLAGS } from '../convex/featureFlags/utils'
import { createLiveToken, liveModelFor } from '../convex/live/createToken'
import { normalizeAgentCostMetric } from '../convex/telemetry/agentPricing'

afterEach(() => {
    vi.unstubAllGlobals()
    vi.unstubAllEnvs()
})

describe('native model rollback', () => {
    it('defaults to the new model and keeps incompatible clients pinned', () => {
        expect(
            KNOWN_FLAGS.find((f) => f.key === 'agentGemini31')
                ?.enabledByDefault,
        ).toBe(false)
        for (const platform of ['android', 'ios', 'macos']) {
            expect(liveModelFor(platform, '0.5.1')).toBe('gemini-3.8-live')
            expect(
                liveModelFor(platform, '0.5.1', { agentGemini31: false }),
            ).toBe('gemini-3.8-live')
            expect(
                liveModelFor(platform, '0.5.1', { agentGemini31: true }),
            ).toBe('gemini-3.1-flash-live-preview')
            expect(
                liveModelFor(platform, '0.5.0', { agentGemini31: true }),
            ).toBe('gemini-3.8-live')
            expect(
                liveModelFor(platform, '0.4.0', { agentGemini31: false }),
            ).toBe('gemini-3.1-flash-live-preview')
        }
        expect(liveModelFor('web', '0.0.0', { agentGemini31: false })).toBe(
            'gemini-3.1-flash-live-preview',
        )
    })

    it.each([
        false,
        true,
    ])('mints matching constraints with rollback=%s', async (rollback) => {
        vi.stubEnv('GEMINI_API_KEY', 'test-key')
        const fetchMock = vi.fn(
            async () =>
                new Response(JSON.stringify({ name: 'auth_tokens/test' })),
        )
        vi.stubGlobal('fetch', fetchMock)
        const result = await createLiveToken({
            platform: 'android',
            appVersion: '0.5.1',
            flags: { agentGemini31: rollback },
        })
        const request = JSON.parse(
            (fetchMock.mock.calls[0] as unknown as [string, RequestInit])[1]
                .body as string,
        )
        const setup = request.bidiGenerateContentSetup
        expect(result.model).toBe(
            rollback ? 'gemini-3.1-flash-live-preview' : 'gemini-3.8-live',
        )
        expect(setup.model).toBe(`models/${result.model}`)
        expect(setup.tools[0].functionDeclarations.length).toBeGreaterThan(0)
        for (const tool of setup.tools[0].functionDeclarations) {
            expect(tool.behavior).toBe(rollback ? undefined : 'BLOCKING')
        }
        expect(setup.generationConfig.responseModalities).toEqual(['AUDIO'])
    })
})

it.each([
    'gemini-3.8-live',
    'gemini-3.1-flash-live-preview',
])('backend accepts cost metrics and preserves model %s', (model) => {
    const normalized = normalizeAgentCostMetric({
        name: 'agent.interaction.cost_usd',
        timestamp: Date.parse('2026-09-21T00:00:00Z'),
        source: 'native',
        type: 'gauge',
        value: 999,
        unit: 'usd',
        attributes: { model, token_input_text: 1000, token_output_audio: 1000 },
    })
    expect(normalized?.attributes?.model).toBe(model)
    expect(normalized?.value).toBeCloseTo(0.01275)
})

it('uses the same flag on updated web while preserving older cached builds', () => {
    expect(liveModelFor('web', '0.5.1')).toBe('gemini-3.8-live')
    expect(liveModelFor('web', '0.5.1', { agentGemini31: true })).toBe(
        'gemini-3.1-flash-live-preview',
    )
    expect(liveModelFor('web', '0.0.0')).toBe('gemini-3.1-flash-live-preview')
})
