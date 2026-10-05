function microphoneConstraints(deviceId?: string): MediaTrackConstraints {
    return {
        ...(deviceId ? { deviceId: { exact: deviceId } } : {}),
        sampleRate: 16000,
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
    }
}

function isMissingDevice(error: unknown): boolean {
    return (
        typeof error === 'object' &&
        error !== null &&
        'name' in error &&
        (error.name === 'OverconstrainedError' ||
            error.name === 'NotFoundError')
    )
}

/** Browser-owned audio resources. Gemini transport stays in the official SDK. */
export async function captureMicrophone(opts: {
    deviceId: string
    signal: AbortSignal
    onAudio: (samples: Float32Array) => void
}) {
    opts.signal.throwIfAborted()
    // `exact`, not `ideal`: with `ideal` the browser weighs the chosen mic
    // against the other constraints and can open a different one, which on a
    // MacBook with the lid closed is a built-in mic that records only zeros.
    let stream: MediaStream
    try {
        stream = await navigator.mediaDevices.getUserMedia({
            audio: microphoneConstraints(opts.deviceId),
        })
    } catch (error) {
        // The chosen mic is gone (unplugged, or ids reset with site data).
        if (!opts.deviceId || !isMissingDevice(error)) throw error
        opts.signal.throwIfAborted()
        stream = await navigator.mediaDevices.getUserMedia({
            audio: microphoneConstraints(),
        })
    }
    let context: AudioContext | undefined
    let worklet: AudioWorkletNode | undefined
    const stop = () => {
        opts.signal.removeEventListener('abort', stop)
        worklet?.port.close()
        worklet?.disconnect()
        for (const track of stream.getTracks()) track.stop()
        if (context?.state !== 'closed') void context?.close().catch(() => {})
    }
    try {
        opts.signal.throwIfAborted()
        opts.signal.addEventListener('abort', stop, { once: true })
        context = new AudioContext({ sampleRate: 16000 })
        await context.audioWorklet.addModule(
            '/audio-processors/capture.worklet.js',
        )
        opts.signal.throwIfAborted()
        await context.resume()
        opts.signal.throwIfAborted()
        worklet = new AudioWorkletNode(context, 'audio-capture-processor')
        worklet.port.onmessage = ({ data }) => {
            if (!opts.signal.aborted) opts.onAudio(data.data as Float32Array)
        }
        context.createMediaStreamSource(stream).connect(worklet)
        // Keep the render graph active; the capture processor outputs silence.
        worklet.connect(context.destination)
        const [track] = stream.getAudioTracks()
        return {
            stop,
            /** The mic actually opened, which may differ after a fallback. */
            deviceId: track?.getSettings().deviceId ?? '',
        }
    } catch (error) {
        stop()
        throw error
    }
}

export function microphonePcm(samples: Float32Array) {
    const bytes = new Uint8Array(samples.length * 2)
    const view = new DataView(bytes.buffer)
    let energy = 0
    for (let i = 0; i < samples.length; i++) {
        const value = Math.max(-1, Math.min(1, samples[i]))
        view.setInt16(i * 2, value * (value < 0 ? 32768 : 32767), true)
        energy += value * value
    }
    let binary = ''
    for (const byte of bytes) binary += String.fromCharCode(byte)
    return {
        data: btoa(binary),
        level: Math.min(1, Math.sqrt(energy / (samples.length || 1)) * 10),
    }
}

/** PCM playback needs only the standard Web Audio API, not a second worklet. */
export class VoicePlayback {
    private context?: AudioContext
    private sources = new Set<AudioBufferSourceNode>()
    private cursor = 0

    async open() {
        this.context ??= new AudioContext({ sampleRate: 24000 })
        await this.context.resume()
    }

    enqueue(data: string, mimeType: string) {
        if (!/^audio\/pcm(?:;|$)/.test(mimeType)) return
        const rate = /(?:^|;)\s*rate=(\d+)/.exec(mimeType)?.[1]
        if (rate && rate !== '24000')
            throw new Error('Unsupported playback sample rate')
        const context = this.context
        if (!context || context.state === 'closed') return
        const binary = atob(data)
        if (binary.length % 2) throw new Error('Unaligned PCM16')
        if (!binary.length) return
        const duration = binary.length / 2 / 24000
        const start = Math.max(context.currentTime, this.cursor)
        if (start + duration - context.currentTime > 20) {
            this.interrupt()
            throw new Error('Playback queue exceeded 20 seconds')
        }
        const buffer = context.createBuffer(1, binary.length / 2, 24000)
        const samples = buffer.getChannelData(0)
        for (let i = 0; i < samples.length; i++) {
            let value =
                binary.charCodeAt(i * 2) | (binary.charCodeAt(i * 2 + 1) << 8)
            if (value >= 32768) value -= 65536
            samples[i] = value / 32768
        }
        const source = context.createBufferSource()
        source.buffer = buffer
        source.connect(context.destination)
        source.onended = () => {
            this.sources.delete(source)
            source.disconnect()
        }
        this.sources.add(source)
        source.start(start)
        this.cursor = start + duration
    }

    interrupt() {
        for (const source of this.sources) {
            source.stop()
            source.disconnect()
        }
        this.sources.clear()
        this.cursor = 0
    }

    close() {
        this.interrupt()
        const context = this.context
        this.context = undefined
        if (context && context.state !== 'closed')
            void context.close().catch(() => {})
    }
}
