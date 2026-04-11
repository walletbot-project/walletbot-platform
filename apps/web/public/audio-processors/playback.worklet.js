/**
 * AudioWorklet processor for playing PCM audio responses.
 * Uses an offset tracker instead of slice() to avoid allocations
 * on the real-time audio thread.
 */
class PCMPlaybackProcessor extends AudioWorkletProcessor {
    constructor() {
        super()
        this.audioQueue = []
        this.currentOffset = 0

        this.port.onmessage = (event) => {
            if (event.data === 'interrupt') {
                this.audioQueue = []
                this.currentOffset = 0
            } else if (event.data instanceof Float32Array) {
                this.audioQueue.push(event.data)
            }
        }
    }

    process(_inputs, outputs) {
        const output = outputs[0]
        if (output.length === 0) return true

        const channel = output[0]
        let i = 0

        while (i < channel.length && this.audioQueue.length > 0) {
            const current = this.audioQueue[0]
            if (!current || current.length === 0) {
                this.audioQueue.shift()
                this.currentOffset = 0
                continue
            }

            const toCopy = Math.min(
                channel.length - i,
                current.length - this.currentOffset,
            )

            for (let j = 0; j < toCopy; j++) {
                channel[i++] = current[this.currentOffset++]
            }

            if (this.currentOffset >= current.length) {
                this.audioQueue.shift()
                this.currentOffset = 0
            }
        }

        // Fill remaining with silence
        while (i < channel.length) {
            channel[i++] = 0
        }

        return true
    }
}

registerProcessor('pcm-processor', PCMPlaybackProcessor)
