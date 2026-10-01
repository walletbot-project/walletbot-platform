import { type LiveConnectParameters, LiveServerMessage } from '@google/genai'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { connectGeminiLive, type LiveSession } from './gemini-live'

const tick = () => new Promise((resolve) => setTimeout(resolve, 0))
function fixture() {
    let params!: LiveConnectParameters
    const session = {
        close: vi.fn(),
        sendRealtimeInput: vi.fn(),
        sendClientContent: vi.fn(),
        sendToolResponse: vi.fn(),
    }
    const connect = vi.fn(async (value: LiveConnectParameters) => {
        params = value
        return session
    })
    return {
        connect,
        session,
        get params() {
            return params
        },
    }
}
afterEach(() => vi.useRealTimers())
describe('official SDK setup boundary', () => {
    for (const model of ['gemini-3.8-live', 'gemini-3.1-flash-live-preview']) {
        it(`waits for setupComplete with ${model}`, async () => {
            const f = fixture()
            let ready = false
            const opening = connectGeminiLive({
                token: 'auth_tokens/test',
                model,
                signal: new AbortController().signal,
                callbacks: { onmessage: vi.fn() },
                connect: f.connect,
            }).then((s) => {
                ready = true
                return s
            })
            await tick()
            expect(ready).toBe(false)
            expect(f.params.model).toBe(model)
            f.params.callbacks.onmessage(
                Object.assign(new LiveServerMessage(), { setupComplete: {} }),
            )
            expect(await opening).toBe(f.session)
        })
    }
    it('closes a session that arrives after cancellation', async () => {
        let resolve!: (session: LiveSession) => void
        const controller = new AbortController()
        const opening = connectGeminiLive({
            token: 'auth_tokens/test',
            model: 'gemini-3.8-live',
            signal: controller.signal,
            callbacks: { onmessage: vi.fn() },
            connect: () =>
                new Promise((done) => {
                    resolve = done
                }),
        })
        const rejected = expect(opening).rejects.toThrow()
        controller.abort()
        await rejected
        const session = {
            close: vi.fn(),
            sendRealtimeInput: vi.fn(),
            sendClientContent: vi.fn(),
            sendToolResponse: vi.fn(),
        }
        resolve(session)
        await tick()
        expect(session.close).toHaveBeenCalledOnce()
    })
    it('closes timed-out setup and rejects early socket close', async () => {
        const f = fixture()
        const opening = connectGeminiLive({
            token: 'auth_tokens/test',
            model: 'gemini-3.8-live',
            signal: new AbortController().signal,
            callbacks: { onmessage: vi.fn() },
            connect: f.connect,
        })
        const rejected = expect(opening).rejects.toThrow('closed before setup')
        await tick()
        f.params.callbacks.onclose?.({ code: 1006 } as CloseEvent)
        await rejected
        expect(f.session.close).toHaveBeenCalledOnce()
    })
    it('times out even if the SDK has not returned a socket yet', async () => {
        vi.useFakeTimers()
        const opening = connectGeminiLive({
            token: 'auth_tokens/test',
            model: 'gemini-3.8-live',
            signal: new AbortController().signal,
            callbacks: { onmessage: vi.fn() },
            connect: () => new Promise(() => {}),
            timeoutMs: 100,
        })
        const rejected = expect(opening).rejects.toThrow('timed out')
        await vi.advanceTimersByTimeAsync(100)
        await rejected
    })
})
