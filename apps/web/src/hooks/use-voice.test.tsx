// @vitest-environment jsdom

import { LiveServerMessage } from '@google/genai'
import { act, useLayoutEffect } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import type { LiveSession } from '@/lib/gemini-live'
import { useVoice } from './use-voice'

const f = vi.hoisted(() => {
    const voice = new Proxy(
        {},
        {
            get: (_, key) =>
                String(key).startsWith('system')
                    ? () => String(key)
                    : String(key),
        },
    )
    return {
        client: { action: vi.fn() },
        catalog: { voice },
        connect: vi.fn(),
        capture: vi.fn(),
        execute: vi.fn(),
        recorder: {
            sessionId: 'test-session',
            open: vi.fn(),
            record: vi.fn(),
            end: vi.fn(),
            markStatus: vi.fn(),
        },
        playback: {
            open: vi.fn(async () => {}),
            close: vi.fn(),
            interrupt: vi.fn(),
            enqueue: vi.fn(),
        },
        metrics: {
            recordSetupComplete: vi.fn(),
            recordFirstResponse: vi.fn(),
        },
    }
})
vi.mock('convex/react', () => ({
    useConvex: () => f.client,
    useQuery: () => 'owner',
}))
vi.mock('@/lib/i18n', () => ({ useT: () => f.catalog }))
vi.mock('@/lib/agent-tools', () => ({ executeToolCall: f.execute }))
vi.mock('@/lib/voice-history', () => ({
    createVoiceHistoryRecorder: () => f.recorder,
}))
vi.mock('@/lib/gemini-live', () => ({
    WEB_LIVE_VERSION: '0.5.1',
    connectGeminiLive: f.connect,
}))
vi.mock('@/lib/agent-metrics', () => f.metrics)
vi.mock('@/lib/voice-audio', async (importOriginal) => ({
    ...(await importOriginal<object>()),
    captureMicrophone: f.capture,
    VoicePlayback: class {
        open = f.playback.open
        close = f.playback.close
        interrupt = f.playback.interrupt
        enqueue = f.playback.enqueue
    },
}))
let root: Root
let voice: ReturnType<typeof useVoice>
let ready: (session: LiveSession) => void
let receive: (message: LiveServerMessage) => void
const onmessage = (message: Partial<LiveServerMessage>) =>
    receive(Object.assign(new LiveServerMessage(), message))
let onclose: (event: CloseEvent) => void
let onAudio: (audio: Float32Array) => void
let opening: Promise<void>
const session = {
    sendRealtimeInput: vi.fn(),
    sendClientContent: vi.fn(),
    sendToolResponse: vi.fn(),
    close: vi.fn(),
} satisfies LiveSession
const tick = () => new Promise((resolve) => setTimeout(resolve, 0))
function Harness() {
    const current = useVoice({ context: { client: f.client as never } })
    useLayoutEffect(() => {
        voice = current
    })
    return null
}
beforeEach(async () => {
    vi.clearAllMocks()
    localStorage.clear()
    vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true)
    Object.defineProperty(navigator, 'mediaDevices', {
        configurable: true,
        value: {
            enumerateDevices: async () => [],
            addEventListener: vi.fn(),
            removeEventListener: vi.fn(),
        },
    })
    f.client.action.mockResolvedValue({
        token: 'auth_tokens/test',
        model: 'gemini-3.8-live',
    })
    f.connect.mockImplementation((opts) => {
        receive = opts.callbacks.onmessage
        onclose = opts.callbacks.onclose
        return new Promise((resolve) => {
            ready = resolve
        })
    })
    f.capture.mockImplementation(async (opts) => {
        onAudio = opts.onAudio
        return { stop: vi.fn() }
    })
    root = createRoot(document.createElement('div'))
    await act(async () => {
        root.render(<Harness />)
        await tick()
    })
})
afterEach(async () => {
    await act(async () => {
        root.unmount()
        await tick()
    })
    vi.unstubAllGlobals()
})
async function start(mode: 'audio' | 'text' = 'audio') {
    await act(async () => {
        opening = voice.connect(mode)
        await tick()
    })
}
async function establish() {
    await act(async () => {
        ready(session)
        await opening
    })
}
it('buffers speech before setup, sends it once, and advertises the new web version', async () => {
    await start()
    expect(voice.isMicOn).toBe(true)
    expect(voice.isConnecting).toBe(true)
    expect(f.client.action).toHaveBeenCalledWith(expect.anything(), {
        platform: 'web',
        appVersion: '0.5.1',
    })
    await act(async () => {
        onAudio(new Float32Array([0.5, 0.1]))
    })
    expect(session.sendRealtimeInput).not.toHaveBeenCalled()
    await establish()
    expect(voice.isConnected).toBe(true)
    expect(session.sendRealtimeInput).toHaveBeenCalledOnce()
    await act(async () => {
        onAudio(new Float32Array([0.2]))
    })
    expect(session.sendRealtimeInput).toHaveBeenCalledTimes(2)
})
it('cancellation while connecting discards buffered speech and prevents restart', async () => {
    await start()
    await act(async () => {
        onAudio(new Float32Array([0.5]))
        voice.setMicOn(false)
    })
    await establish()
    expect(voice.isMicOn).toBe(false)
    expect(session.sendRealtimeInput).not.toHaveBeenCalled()
})
it('a hold released while connecting is sent once connected', async () => {
    await start()
    await act(async () => {
        onAudio(new Float32Array([0.5]))
        onAudio(new Float32Array([0.2]))
        voice.releaseMic()
    })
    expect(voice.isMicOn).toBe(false)
    expect(session.sendRealtimeInput).not.toHaveBeenCalled()
    await establish()
    const audio = {
        audio: expect.objectContaining({ data: expect.any(String) }),
    }
    expect(session.sendRealtimeInput.mock.calls).toEqual([
        [audio],
        [audio],
        [{ audioStreamEnd: true }],
    ])
})
it('silent text never acquires audio and preserves both usage and content in combined messages', async () => {
    await start('text')
    await establish()
    expect(f.capture).not.toHaveBeenCalled()
    expect(f.playback.open).not.toHaveBeenCalled()
    await act(async () => {
        onmessage({
            usageMetadata: { promptTokenCount: 10, responseTokenCount: 5 },
            serverContent: {
                outputTranscription: { text: 'Hello' },
                modelTurn: {
                    parts: [
                        { text: 'Hello' },
                        { text: 'hidden', thought: true },
                    ],
                },
                turnComplete: true,
            },
        })
    })
    expect(voice.messages.filter((m) => m.kind === 'agent')).toMatchObject([
        { text: 'Hello' },
    ])
    expect(f.recorder.record).toHaveBeenCalledWith(
        'usage_metadata',
        'server',
        expect.objectContaining({ model: 'gemini-3.8-live' }),
        undefined,
    )
})
it('deduplicates tools, cancels queued work, and records committed results without replying to a dead connection', async () => {
    await start('text')
    await establish()
    let finish!: (result: object) => void
    f.execute.mockImplementation(
        () =>
            new Promise((resolve) => {
                finish = resolve
            }),
    )
    await act(async () => {
        onmessage({
            toolCall: {
                functionCalls: [
                    { id: 'a', name: 'calculate', args: {} },
                    { id: 'b', name: 'calculate', args: {} },
                ],
            },
        })
        onmessage({
            toolCall: {
                functionCalls: [{ id: 'a', name: 'calculate', args: {} }],
            },
        })
        await tick()
        onmessage({ toolCallCancellation: { ids: ['b'] } })
        onclose({ code: 1006, reason: 'network lost' } as CloseEvent)
        finish({ ok: true })
        await tick()
    })
    expect(f.execute).toHaveBeenCalledOnce()
    expect(session.sendToolResponse).not.toHaveBeenCalled()
    expect(f.recorder.record).toHaveBeenCalledWith(
        'tool_result',
        'client',
        expect.objectContaining({ id: 'a', result: { ok: true } }),
        'tool',
    )
})
it('bounds startup audio and never sends a truncated buffer after overflow', async () => {
    await start()
    await act(async () => {
        onAudio(new Float32Array(16000 * 5 + 1))
    })
    expect(voice.isMicOn).toBe(false)
    await establish()
    expect(session.sendRealtimeInput).not.toHaveBeenCalled()
})
it('a cancelled permission request does not block or stop its replacement', async () => {
    await start('text')
    await establish()
    let finishOld!: (capture: { stop: () => void }) => void
    f.capture.mockImplementationOnce(
        () =>
            new Promise((resolve) => {
                finishOld = resolve
            }),
    )
    let oldOpening!: Promise<void>
    await act(async () => {
        oldOpening = voice.openMic()
        await tick()
    })
    await act(async () => {
        voice.setMicOn(false)
        await voice.openMic()
    })
    expect(voice.isMicOn).toBe(true)
    const oldStop = vi.fn()
    await act(async () => {
        finishOld({ stop: oldStop })
        await oldOpening
    })
    expect(oldStop).toHaveBeenCalledOnce()
    expect(voice.isMicOn).toBe(true)
    expect(voice.isMicCaptureActive).toBe(true)
})

it('remembers the chosen microphone on remount while recording stays off', async () => {
    await act(async () => {
        await voice.handleDeviceChange('usb-mic')
    })
    expect(localStorage.getItem('voice_microphone_device')).toBe('usb-mic')
    await act(async () => {
        root.unmount()
    })
    root = createRoot(document.createElement('div'))
    await act(async () => {
        root.render(<Harness />)
        await tick()
    })
    expect(voice.selectedDeviceId).toBe('usb-mic')
    expect(voice.isMicOn).toBe(false)
    expect(f.capture).not.toHaveBeenCalled()
})

it('shows the fallback microphone but retries the chosen one on the next open', async () => {
    await act(async () => {
        await voice.handleDeviceChange('usb-mic')
    })
    await start('text')
    await establish()
    f.capture.mockImplementationOnce(async (opts) => {
        onAudio = opts.onAudio
        return { stop: vi.fn(), deviceId: 'built-in' }
    })
    await act(async () => {
        await voice.openMic()
    })
    expect(voice.selectedDeviceId).toBe('built-in')

    await act(async () => {
        voice.setMicOn(false)
        await voice.openMic()
    })
    expect(f.capture).toHaveBeenLastCalledWith(
        expect.objectContaining({ deviceId: 'usb-mic' }),
    )
})

it('unavailable storage does not block choosing or using a microphone', async () => {
    const write = vi
        .spyOn(Storage.prototype, 'setItem')
        .mockImplementation(() => {
            throw new DOMException('Storage unavailable', 'SecurityError')
        })
    try {
        await act(async () => {
            await voice.handleDeviceChange('usb-mic')
        })
        await start()
        await establish()
        expect(voice.selectedDeviceId).toBe('usb-mic')
        expect(f.capture).toHaveBeenCalledWith(
            expect.objectContaining({ deviceId: 'usb-mic' }),
        )
        expect(voice.isMicOn).toBe(true)
    } finally {
        write.mockRestore()
    }
})

it('leaving the screen releases capture and returning does not restart recording', async () => {
    const stop = vi.fn()
    f.capture.mockResolvedValueOnce({ stop })
    await start()
    await establish()
    await act(async () => {
        voice.detach()
        voice.attach()
    })
    expect(stop).toHaveBeenCalledOnce()
    expect(voice.isMicOn).toBe(false)
    expect(voice.isMicCaptureActive).toBe(false)
    expect(voice.isConnected).toBe(true)
    expect(f.capture).toHaveBeenCalledOnce()
    expect(f.playback.close).toHaveBeenCalled()
})

it('reports setup completion per connect, resumed only after a failed attempt', async () => {
    await start('text')
    await establish()
    expect(f.metrics.recordSetupComplete).toHaveBeenCalledOnce()
    expect(f.metrics.recordSetupComplete).toHaveBeenLastCalledWith({
        elapsedMs: expect.any(Number),
        resumed: false,
    })
    vi.useFakeTimers()
    try {
        await act(async () => {
            onclose({ code: 1006, reason: 'network lost' } as CloseEvent)
            vi.advanceTimersByTime(1000)
        })
    } finally {
        vi.useRealTimers()
    }
    await act(async () => {
        await tick()
        ready(session)
        await tick()
    })
    expect(voice.isConnected).toBe(true)
    expect(f.metrics.recordSetupComplete).toHaveBeenCalledTimes(2)
    expect(f.metrics.recordSetupComplete).toHaveBeenLastCalledWith({
        elapsedMs: expect.any(Number),
        resumed: true,
    })
})
it('times a typed turn to its first transcript delta, once per turn', async () => {
    await start('text')
    await establish()
    await act(async () => {
        onmessage({
            serverContent: { outputTranscription: { text: 'Seed reply' } },
        })
    })
    // No turn was sent yet: nothing to report.
    expect(f.metrics.recordFirstResponse).not.toHaveBeenCalled()
    await act(async () => {
        voice.sendText('coffee 3 dollars')
        onmessage({
            serverContent: { outputTranscription: { text: 'Got' } },
        })
        onmessage({
            serverContent: { outputTranscription: { text: ' it' } },
        })
    })
    expect(f.metrics.recordFirstResponse).toHaveBeenCalledOnce()
    expect(f.metrics.recordFirstResponse).toHaveBeenCalledWith({
        elapsedMs: expect.any(Number),
        mode: 'text',
    })
})
it('times a turn typed before setup from its delayed send', async () => {
    await act(async () => {
        voice.sendText('coffee 3 dollars')
        await tick()
    })
    expect(f.metrics.recordFirstResponse).not.toHaveBeenCalled()
    await act(async () => {
        ready(session)
        await tick()
    })
    expect(session.sendClientContent).toHaveBeenCalled()
    await act(async () => {
        onmessage({
            serverContent: { outputTranscription: { text: 'Got it' } },
        })
    })
    expect(f.metrics.recordFirstResponse).toHaveBeenCalledOnce()
    expect(f.metrics.recordFirstResponse).toHaveBeenCalledWith({
        elapsedMs: expect.any(Number),
        mode: 'text',
    })
})
it('times a spoken turn from the audio stream end to the first audio chunk, even unplayed', async () => {
    await start()
    await establish()
    await act(async () => {
        onAudio(new Float32Array([0.2]))
        voice.setMicOn(false)
    })
    expect(session.sendRealtimeInput).toHaveBeenLastCalledWith({
        audioStreamEnd: true,
    })
    await act(async () => {
        voice.detach()
        onmessage({
            serverContent: {
                modelTurn: {
                    parts: [
                        {
                            inlineData: {
                                data: 'AAAA',
                                mimeType: 'audio/pcm;rate=24000',
                            },
                        },
                    ],
                },
            },
        })
    })
    expect(f.playback.enqueue).not.toHaveBeenCalled()
    expect(f.metrics.recordFirstResponse).toHaveBeenCalledOnce()
    expect(f.metrics.recordFirstResponse).toHaveBeenCalledWith({
        elapsedMs: expect.any(Number),
        mode: 'voice',
    })
})
it('the explicit End drops a pending turn', async () => {
    await start()
    await establish()
    await act(async () => {
        onAudio(new Float32Array([0.2]))
        voice.disconnect()
    })
    await start('text')
    await establish()
    await act(async () => {
        onmessage({
            serverContent: { outputTranscription: { text: 'Hello' } },
        })
    })
    expect(f.metrics.recordFirstResponse).not.toHaveBeenCalled()
})
