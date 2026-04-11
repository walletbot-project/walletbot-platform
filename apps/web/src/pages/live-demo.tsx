import { GoogleGenAI, Modality, type Session } from '@google/genai'
import { Mic, MicOff, Phone, PhoneOff } from 'lucide-react'
import { useCallback, useEffect, useRef, useState } from 'react'

import { Button } from '@/components/ui/button'
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle,
} from '@/components/ui/card'
import { Input } from '@/components/ui/input'

const MODEL = 'gemini-3.1-flash-live-preview'
const INPUT_SAMPLE_RATE = 16000
const OUTPUT_SAMPLE_RATE = 24000
const BUFFER_SIZE = 4096

// ── Audio helpers ──────────────────────────────────────────────

function floatTo16BitPCM(samples: Float32Array): ArrayBuffer {
    const buffer = new ArrayBuffer(samples.length * 2)
    const view = new DataView(buffer)
    for (let i = 0; i < samples.length; i++) {
        const s = Math.max(-1, Math.min(1, samples[i]))
        view.setInt16(i * 2, s < 0 ? s * 0x8000 : s * 0x7fff, true)
    }
    return buffer
}

function pcm16ToFloat32(pcmData: ArrayBuffer): Float32Array {
    const view = new DataView(pcmData)
    const float32 = new Float32Array(pcmData.byteLength / 2)
    for (let i = 0; i < float32.length; i++) {
        float32[i] = view.getInt16(i * 2, true) / 0x8000
    }
    return float32
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer)
    let binary = ''
    for (let i = 0; i < bytes.byteLength; i++) {
        binary += String.fromCharCode(bytes[i])
    }
    return btoa(binary)
}

function base64ToArrayBuffer(base64: string): ArrayBuffer {
    const binary = atob(base64)
    const bytes = new Uint8Array(binary.length)
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i)
    }
    return bytes.buffer
}

function resampleAudio(
    inputData: Float32Array,
    inputRate: number,
    outputRate: number,
): Float32Array {
    if (inputRate === outputRate) return inputData
    const ratio = inputRate / outputRate
    const outputLength = Math.round(inputData.length / ratio)
    const output = new Float32Array(outputLength)
    for (let i = 0; i < outputLength; i++) {
        const srcIndex = i * ratio
        const low = Math.floor(srcIndex)
        const high = Math.min(low + 1, inputData.length - 1)
        const frac = srcIndex - low
        output[i] = inputData[low] * (1 - frac) + inputData[high] * frac
    }
    return output
}

// ── Component ──────────────────────────────────────────────────

type ConnectionStatus = 'disconnected' | 'connecting' | 'connected'

export function LiveDemo() {
    const [apiKey, setApiKey] = useState(
        () => import.meta.env.VITE_GEMINI_API_KEY ?? '',
    )
    const [connectionStatus, setConnectionStatus] =
        useState<ConnectionStatus>('disconnected')
    const [isMuted, setIsMuted] = useState(false)
    const [transcript, setTranscript] = useState<
        { role: 'user' | 'model'; text: string }[]
    >([])

    const sessionRef = useRef<Session | null>(null)
    const audioContextRef = useRef<AudioContext | null>(null)
    const mediaStreamRef = useRef<MediaStream | null>(null)
    const processorRef = useRef<ScriptProcessorNode | null>(null)
    const sourceRef = useRef<MediaStreamAudioSourceNode | null>(null)
    const playbackContextRef = useRef<AudioContext | null>(null)
    const audioQueueRef = useRef<Float32Array[]>([])
    const isPlayingRef = useRef(false)
    const isMutedRef = useRef(false)

    // Keep mute ref in sync
    useEffect(() => {
        isMutedRef.current = isMuted
    }, [isMuted])

    // ── Playback ───────────────────────────────────────────────

    const playNextChunkRef = useRef<() => void>(() => {})

    useEffect(() => {
        playNextChunkRef.current = () => {
            const ctx = playbackContextRef.current
            if (!ctx || audioQueueRef.current.length === 0) {
                isPlayingRef.current = false
                return
            }

            isPlayingRef.current = true
            const samples = audioQueueRef.current.shift()!
            const buffer = ctx.createBuffer(
                1,
                samples.length,
                OUTPUT_SAMPLE_RATE,
            )
            buffer.getChannelData(0).set(samples)

            const source = ctx.createBufferSource()
            source.buffer = buffer
            source.connect(ctx.destination)
            source.onended = () => playNextChunkRef.current()
            source.start()
        }
    }, [])

    const enqueueAudio = useCallback((base64Data: string) => {
        const pcm = base64ToArrayBuffer(base64Data)
        const float32 = pcm16ToFloat32(pcm)
        audioQueueRef.current.push(float32)

        if (!isPlayingRef.current) {
            playNextChunkRef.current()
        }
    }, [])

    // ── Connect / Disconnect ───────────────────────────────────

    const connect = useCallback(async () => {
        if (!apiKey.trim()) return

        setConnectionStatus('connecting')
        setTranscript([])
        audioQueueRef.current = []

        try {
            const ai = new GoogleGenAI({ apiKey: apiKey.trim() })

            // Playback context
            playbackContextRef.current = new AudioContext({
                sampleRate: OUTPUT_SAMPLE_RATE,
            })

            const session = await ai.live.connect({
                model: MODEL,
                config: {
                    responseModalities: [Modality.AUDIO],
                },
                callbacks: {
                    onopen: () => {
                        setConnectionStatus('connected')
                    },
                    onmessage: (message) => {
                        // Handle audio response
                        const parts =
                            message.serverContent?.modelTurn?.parts ?? []
                        for (const part of parts) {
                            if (part.inlineData?.data) {
                                enqueueAudio(part.inlineData.data)
                            }
                            if (part.text) {
                                setTranscript((prev) => [
                                    ...prev,
                                    { role: 'model', text: part.text! },
                                ])
                            }
                        }
                    },
                    onerror: (e) => {
                        console.error('Live API error:', e.message)
                        setConnectionStatus('disconnected')
                    },
                    onclose: () => {
                        setConnectionStatus('disconnected')
                    },
                },
            })

            sessionRef.current = session

            // Mic capture
            const stream = await navigator.mediaDevices.getUserMedia({
                audio: {
                    sampleRate: INPUT_SAMPLE_RATE,
                    channelCount: 1,
                    echoCancellation: true,
                    noiseSuppression: true,
                },
            })
            mediaStreamRef.current = stream

            const audioCtx = new AudioContext()
            audioContextRef.current = audioCtx

            const source = audioCtx.createMediaStreamSource(stream)
            sourceRef.current = source

            const processor = audioCtx.createScriptProcessor(BUFFER_SIZE, 1, 1)
            processorRef.current = processor

            processor.onaudioprocess = (e) => {
                if (isMutedRef.current || !sessionRef.current) return

                const inputData = e.inputBuffer.getChannelData(0)
                const resampled = resampleAudio(
                    inputData,
                    audioCtx.sampleRate,
                    INPUT_SAMPLE_RATE,
                )
                const pcm = floatTo16BitPCM(resampled)
                const base64 = arrayBufferToBase64(pcm)

                sessionRef.current.sendRealtimeInput({
                    audio: {
                        data: base64,
                        mimeType: `audio/pcm;rate=${INPUT_SAMPLE_RATE}`,
                    },
                })
            }

            source.connect(processor)
            processor.connect(audioCtx.destination)
        } catch (err) {
            console.error('Failed to connect:', err)
            setConnectionStatus('disconnected')
        }
    }, [apiKey, enqueueAudio])

    const disconnect = useCallback(() => {
        processorRef.current?.disconnect()
        sourceRef.current?.disconnect()
        for (const track of mediaStreamRef.current?.getTracks() ?? []) {
            track.stop()
        }
        audioContextRef.current?.close()
        playbackContextRef.current?.close()
        sessionRef.current?.close()

        processorRef.current = null
        sourceRef.current = null
        mediaStreamRef.current = null
        audioContextRef.current = null
        playbackContextRef.current = null
        sessionRef.current = null
        audioQueueRef.current = []
        isPlayingRef.current = false

        setConnectionStatus('disconnected')
    }, [])

    // Cleanup on unmount
    useEffect(() => disconnect, [disconnect])

    // ── Render ─────────────────────────────────────────────────

    const isConnected = connectionStatus === 'connected'
    const isConnecting = connectionStatus === 'connecting'

    return (
        <div className="flex min-h-screen items-center justify-center bg-background p-4">
            <Card className="w-full max-w-md">
                <CardHeader>
                    <CardTitle>Gemini Live Demo</CardTitle>
                    <CardDescription>
                        Real-time audio conversation with Gemini 3.1 Flash
                    </CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                    {/* API Key */}
                    <div className="flex flex-col gap-1.5">
                        <label
                            htmlFor="api-key"
                            className="text-sm font-medium"
                        >
                            API Key
                        </label>
                        <Input
                            id="api-key"
                            type="password"
                            placeholder="Enter your Gemini API key"
                            value={apiKey}
                            onChange={(e) => setApiKey(e.target.value)}
                            disabled={connectionStatus !== 'disconnected'}
                        />
                        <p className="text-xs text-muted-foreground">
                            Stored in browser memory only. Set{' '}
                            <code className="text-xs">VITE_GEMINI_API_KEY</code>{' '}
                            to prefill.
                        </p>
                    </div>

                    {/* Status */}
                    <div className="flex items-center gap-2">
                        <div
                            className={`size-2 rounded-full ${
                                isConnected
                                    ? 'bg-green-500'
                                    : isConnecting
                                      ? 'bg-yellow-500 animate-pulse'
                                      : 'bg-muted-foreground/40'
                            }`}
                        />
                        <span className="text-sm text-muted-foreground">
                            {isConnected
                                ? 'Connected — speak into your mic'
                                : isConnecting
                                  ? 'Connecting...'
                                  : 'Disconnected'}
                        </span>
                    </div>

                    {/* Controls */}
                    <div className="flex gap-2">
                        {connectionStatus === 'disconnected' ? (
                            <Button
                                onClick={connect}
                                disabled={!apiKey.trim()}
                                className="flex-1"
                            >
                                <Phone />
                                Connect
                            </Button>
                        ) : (
                            <>
                                <Button
                                    variant="destructive"
                                    onClick={disconnect}
                                    className="flex-1"
                                >
                                    <PhoneOff />
                                    Disconnect
                                </Button>
                                <Button
                                    variant={isMuted ? 'secondary' : 'outline'}
                                    size="icon"
                                    onClick={() => setIsMuted((m) => !m)}
                                >
                                    {isMuted ? <MicOff /> : <Mic />}
                                </Button>
                            </>
                        )}
                    </div>

                    {/* Transcript (text parts, if any) */}
                    {transcript.length > 0 && (
                        <div className="flex max-h-48 flex-col gap-1 overflow-y-auto rounded-lg border p-3">
                            {transcript.map((entry, i) => (
                                <p
                                    key={i}
                                    className={`text-sm ${
                                        entry.role === 'model'
                                            ? 'text-foreground'
                                            : 'text-muted-foreground'
                                    }`}
                                >
                                    <span className="font-medium">
                                        {entry.role === 'model'
                                            ? 'Gemini'
                                            : 'You'}
                                        :
                                    </span>{' '}
                                    {entry.text}
                                </p>
                            ))}
                        </div>
                    )}
                </CardContent>
            </Card>
        </div>
    )
}
