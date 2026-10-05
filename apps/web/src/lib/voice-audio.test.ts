import { afterEach, expect, it, vi } from 'vitest'
import { captureMicrophone, microphonePcm, VoicePlayback } from './voice-audio'

afterEach(() => vi.unstubAllGlobals())
it('encodes little-endian PCM16 and clips microphone samples', () => {
    const { data, level } = microphonePcm(new Float32Array([-2, 0, 2]))
    expect([...atob(data)].map((c) => c.charCodeAt(0))).toEqual([
        0, 128, 0, 0, 255, 127,
    ])
    expect(level).toBe(1)
})
it('stops a microphone granted after cancellation without opening an audio graph', async () => {
    let grant!: (stream: { getTracks: () => { stop: () => void }[] }) => void
    const stop = vi.fn()
    vi.stubGlobal('navigator', {
        mediaDevices: {
            getUserMedia: () =>
                new Promise((resolve) => {
                    grant = resolve
                }),
        },
    })
    const context = vi.fn()
    vi.stubGlobal('AudioContext', context)
    const controller = new AbortController()
    const opening = captureMicrophone({
        deviceId: '',
        signal: controller.signal,
        onAudio: vi.fn(),
    })
    controller.abort()
    grant({ getTracks: () => [{ stop }] })
    await expect(opening).rejects.toThrow()
    expect(stop).toHaveBeenCalledOnce()
    expect(context).not.toHaveBeenCalled()
})
it('uses bounded standard Web Audio playback and interrupts scheduled sources', async () => {
    const sources: {
        start: ReturnType<typeof vi.fn>
        stop: ReturnType<typeof vi.fn>
        disconnect: ReturnType<typeof vi.fn>
    }[] = []
    const close = vi.fn(async () => {})
    vi.stubGlobal(
        'AudioContext',
        class {
            state = 'running'
            currentTime = 1
            destination = {}
            resume = async () => {}
            close = close
            createBuffer(_channels: number, length: number) {
                return { getChannelData: () => new Float32Array(length) }
            }
            createBufferSource() {
                const source = {
                    connect: vi.fn(),
                    disconnect: vi.fn(),
                    start: vi.fn(),
                    stop: vi.fn(),
                }
                sources.push(source)
                return source
            }
        },
    )
    const playback = new VoicePlayback()
    await playback.open()
    playback.enqueue(btoa('\0\0'), 'audio/pcm;rate=24000')
    playback.enqueue(btoa('\0\0'), 'audio/pcm;rate=24000')
    expect(sources[0].start).toHaveBeenCalledWith(1)
    expect(sources[1].start).toHaveBeenCalledWith(1 + 1 / 24000)
    playback.interrupt()
    expect(sources.every((source) => source.stop.mock.calls.length === 1)).toBe(
        true,
    )
    expect(() => playback.enqueue(btoa('\0'), 'audio/pcm')).toThrow('Unaligned')
    expect(() =>
        playback.enqueue(btoa('\0\0'), 'audio/pcm;rate=16000'),
    ).toThrow('sample rate')
    expect(() =>
        playback.enqueue(btoa('\0'.repeat(24000 * 2 * 21)), 'audio/pcm'),
    ).toThrow('20 seconds')
    playback.close()
    expect(close).toHaveBeenCalledOnce()
})

function stubAudioGraph() {
    vi.stubGlobal(
        'AudioContext',
        class {
            state = 'running'
            sampleRate = 16000
            destination = {}
            audioWorklet = { addModule: async () => {} }
            resume = async () => {}
            close = async () => {}
            createMediaStreamSource = () => ({ connect: () => {} })
        },
    )
    vi.stubGlobal(
        'AudioWorkletNode',
        class {
            port = { onmessage: null, close: () => {} }
            connect = () => {}
            disconnect = () => {}
        },
    )
}

function stream(deviceId: string) {
    const track = {
        label: deviceId,
        muted: false,
        enabled: true,
        readyState: 'live',
        stop: () => {},
        getSettings: () => ({ deviceId }),
    }
    return { getTracks: () => [track], getAudioTracks: () => [track] }
}

it('opens exactly the chosen microphone', async () => {
    stubAudioGraph()
    const getUserMedia = vi.fn(async () => stream('usb'))
    vi.stubGlobal('navigator', { mediaDevices: { getUserMedia } })

    const microphone = await captureMicrophone({
        deviceId: 'usb',
        signal: new AbortController().signal,
        onAudio: () => {},
    })

    expect(getUserMedia).toHaveBeenCalledTimes(1)
    expect(getUserMedia.mock.calls[0]).toMatchObject([
        { audio: { deviceId: { exact: 'usb' } } },
    ])
    expect(microphone.deviceId).toBe('usb')
})

it('falls back to the default microphone when the chosen one is gone', async () => {
    stubAudioGraph()
    const getUserMedia = vi
        .fn()
        .mockRejectedValueOnce({ name: 'OverconstrainedError' })
        .mockResolvedValueOnce(stream('built-in'))
    vi.stubGlobal('navigator', { mediaDevices: { getUserMedia } })

    const microphone = await captureMicrophone({
        deviceId: 'unplugged',
        signal: new AbortController().signal,
        onAudio: () => {},
    })

    expect(getUserMedia).toHaveBeenCalledTimes(2)
    expect(getUserMedia.mock.calls[1][0].audio).not.toHaveProperty('deviceId')
    expect(microphone.deviceId).toBe('built-in')
})

it('does not retry a denied permission on another microphone', async () => {
    stubAudioGraph()
    const getUserMedia = vi.fn().mockRejectedValue({ name: 'NotAllowedError' })
    vi.stubGlobal('navigator', { mediaDevices: { getUserMedia } })

    await expect(
        captureMicrophone({
            deviceId: 'usb',
            signal: new AbortController().signal,
            onAudio: () => {},
        }),
    ).rejects.toMatchObject({ name: 'NotAllowedError' })
    expect(getUserMedia).toHaveBeenCalledTimes(1)
})
