import { afterEach, describe, expect, it, vi } from 'vitest'
import {
    createLiveToken,
    type LiveTurnDetection,
} from '../convex/live/createToken'

afterEach(() => {
    vi.unstubAllGlobals()
    vi.unstubAllEnvs()
})

async function mintedSetup(turnDetection?: LiveTurnDetection) {
    vi.stubEnv('GEMINI_API_KEY', 'test-key')
    const fetchMock = vi.fn(
        async () => new Response(JSON.stringify({ name: 'auth_tokens/test' })),
    )
    vi.stubGlobal('fetch', fetchMock)
    await createLiveToken({
        platform: 'web',
        appVersion: '0.5.1',
        turnDetection,
    })
    const request = JSON.parse(
        (fetchMock.mock.calls[0] as unknown as [string, RequestInit])[1]
            .body as string,
    )
    return request.bidiGenerateContentSetup
}

describe('live turn detection', () => {
    it('turns voice activity detection off for manual turns', async () => {
        const setup = await mintedSetup('manual')
        expect(setup.realtimeInputConfig).toEqual({
            automaticActivityDetection: { disabled: true },
        })
    })

    it.each([
        'auto',
        undefined,
    ] as const)('leaves voice activity detection on for %s', async (turnDetection) => {
        const setup = await mintedSetup(turnDetection)
        expect(setup.realtimeInputConfig).toBeUndefined()
    })
})
