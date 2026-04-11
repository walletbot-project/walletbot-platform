/**
 * AudioWorklet processor for capturing microphone audio.
 * Buffers incoming samples into 512-sample chunks (~32ms at 16kHz)
 * per Gemini best practices (20-40ms chunks).
 */
class AudioCaptureProcessor extends AudioWorkletProcessor {
    constructor() {
        super()
        this.bufferSize = 512
        this.buffer = new Float32Array(this.bufferSize)
        this.bufferIndex = 0
    }

    process(inputs) {
        const input = inputs[0]
        if (!input || input.length === 0) return true

        const channel = input[0]
        for (let i = 0; i < channel.length; i++) {
            this.buffer[this.bufferIndex++] = channel[i]

            if (this.bufferIndex >= this.bufferSize) {
                this.port.postMessage({
                    type: 'audio',
                    data: this.buffer.slice(),
                })
                this.bufferIndex = 0
            }
        }

        return true
    }
}

registerProcessor('audio-capture-processor', AudioCaptureProcessor)
