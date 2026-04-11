import { api } from '@wallet-bot/backend/api'
import { ConvexHttpClient } from 'convex/browser'
import {
    ChevronDown,
    ExternalLink,
    Mic,
    MicOff,
    Phone,
    PhoneOff,
    Wrench,
} from 'lucide-react'
import { useCallback, useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'

import { Button } from '@/components/ui/button'
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle,
} from '@/components/ui/card'
import {
    EXPENSE_SYSTEM_INSTRUCTION,
    executeToolCall,
    expenseToolDeclarations,
} from '@/lib/expense-tools'

const convexClient = new ConvexHttpClient(
    import.meta.env.VITE_CONVEX_URL as string,
)

const INPUT_SAMPLE_RATE = 16000
const OUTPUT_SAMPLE_RATE = 24000

const WS_BASE_URL =
    'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained'

// ── Audio helpers ──────────────────────────────────────────────

function floatTo16BitPCM(float32: Float32Array): ArrayBuffer {
    const int16 = new Int16Array(float32.length)
    for (let i = 0; i < float32.length; i++) {
        int16[i] = Math.max(-1, Math.min(1, float32[i])) * 0x7fff
    }
    return int16.buffer
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer)
    let binary = ''
    for (let i = 0; i < bytes.byteLength; i++) {
        binary += String.fromCharCode(bytes[i])
    }
    return btoa(binary)
}

function base64ToPcmFloat32(base64: string): Float32Array {
    const binary = atob(base64)
    const bytes = new Uint8Array(binary.length)
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i)
    }
    const int16 = new Int16Array(bytes.buffer)
    const float32 = new Float32Array(int16.length)
    for (let i = 0; i < int16.length; i++) {
        float32[i] = int16[i] / 32768
    }
    return float32
}

function computeRMS(float32: Float32Array): number {
    let sum = 0
    for (let i = 0; i < float32.length; i++) {
        sum += float32[i] * float32[i]
    }
    return Math.sqrt(sum / float32.length)
}

// ── Component ──────────────────────────────────────────────────

type ConnectionStatus = 'disconnected' | 'connecting' | 'connected'
type TurnStatus = 'idle' | 'user-speaking' | 'ai-speaking'

export function LiveDemoCloud() {
    const [connectionStatus, setConnectionStatus] =
        useState<ConnectionStatus>('disconnected')
    const [isMuted, setIsMuted] = useState(false)
    const [error, setError] = useState<string | null>(null)
    const [turnStatus, setTurnStatus] = useState<TurnStatus>('idle')
    const [micLevel, setMicLevel] = useState(0)
    const [toolStatus, setToolStatus] = useState<string | null>(null)
    const [transcript, setTranscript] = useState<
        { role: 'user' | 'model' | 'tool'; text: string }[]
    >([])

    const wsRef = useRef<WebSocket | null>(null)
    const captureContextRef = useRef<AudioContext | null>(null)
    const captureWorkletRef = useRef<AudioWorkletNode | null>(null)
    const mediaStreamRef = useRef<MediaStream | null>(null)
    const playbackContextRef = useRef<AudioContext | null>(null)
    const playbackWorkletRef = useRef<AudioWorkletNode | null>(null)
    const isMutedRef = useRef(false)

    useEffect(() => {
        isMutedRef.current = isMuted
    }, [isMuted])

    // ── Mic capture (16kHz AudioWorklet) ───────────────────────

    const startMicCapture = useCallback(async () => {
        console.debug('[mic] requesting microphone access')
        const stream = await navigator.mediaDevices.getUserMedia({
            audio: {
                sampleRate: INPUT_SAMPLE_RATE,
                channelCount: 1,
                echoCancellation: true,
                noiseSuppression: true,
                autoGainControl: true,
            },
        })
        mediaStreamRef.current = stream
        console.debug(
            '[mic] got stream, tracks:',
            stream.getAudioTracks().length,
        )

        const captureCtx = new AudioContext({ sampleRate: INPUT_SAMPLE_RATE })
        console.debug(
            '[mic] AudioContext created, sampleRate:',
            captureCtx.sampleRate,
        )
        await captureCtx.audioWorklet.addModule(
            '/audio-processors/capture.worklet.js',
        )

        const worklet = new AudioWorkletNode(
            captureCtx,
            'audio-capture-processor',
        )

        worklet.port.onmessage = (event: MessageEvent) => {
            const float32: Float32Array = event.data.data

            // Always compute mic level for the meter
            const rms = computeRMS(float32)
            // Normalize to 0–1 (RMS of speech is typically 0.01–0.15)
            setMicLevel(Math.min(1, rms * 10))

            if (isMutedRef.current) return

            const ws = wsRef.current
            if (!ws || ws.readyState !== WebSocket.OPEN) return

            const pcm = floatTo16BitPCM(float32)
            const base64 = arrayBufferToBase64(pcm)

            ws.send(
                JSON.stringify({
                    realtimeInput: {
                        audio: {
                            data: base64,
                            mimeType: 'audio/pcm',
                        },
                    },
                }),
            )
        }

        const source = captureCtx.createMediaStreamSource(stream)
        source.connect(worklet)

        captureContextRef.current = captureCtx
        captureWorkletRef.current = worklet
    }, [])

    // ── Connect ────────────────────────────────────────────────

    const connect = useCallback(async () => {
        setConnectionStatus('connecting')
        setError(null)
        setTranscript([])
        setTurnStatus('idle')
        setToolStatus(null)
        setMicLevel(0)

        try {
            // 1. Get ephemeral token from Convex
            console.debug('[connect] requesting ephemeral token')
            const { token, model } = await convexClient.action(
                api.live.actions.requestLiveToken,
                {},
            )

            // 2. Open WebSocket to Gemini v1alpha constrained endpoint
            console.debug('[connect] token received, opening WebSocket')
            const ws = new WebSocket(`${WS_BASE_URL}?access_token=${token}`)
            wsRef.current = ws

            // 3. Init playback (24kHz AudioWorklet)
            const playbackCtx = new AudioContext({
                sampleRate: OUTPUT_SAMPLE_RATE,
            })
            await playbackCtx.audioWorklet.addModule(
                '/audio-processors/playback.worklet.js',
            )
            const playbackNode = new AudioWorkletNode(
                playbackCtx,
                'pcm-processor',
            )
            playbackNode.connect(playbackCtx.destination)
            playbackContextRef.current = playbackCtx
            playbackWorkletRef.current = playbackNode

            // 4. WebSocket handlers
            ws.onopen = () => {
                console.debug(
                    '[ws] connected, sending setup with tools:',
                    expenseToolDeclarations.map((t) => t.name),
                )
                ws.send(
                    JSON.stringify({
                        setup: {
                            model: `models/${model}`,
                            generationConfig: {
                                responseModalities: ['AUDIO'],
                            },
                            systemInstruction: {
                                parts: [{ text: EXPENSE_SYSTEM_INSTRUCTION }],
                            },
                            tools: [
                                {
                                    functionDeclarations:
                                        expenseToolDeclarations,
                                },
                            ],
                        },
                    }),
                )
            }

            ws.onmessage = async (event) => {
                let data: string
                if (event.data instanceof Blob) {
                    data = await event.data.text()
                } else {
                    data = event.data
                }

                const msg = JSON.parse(data)
                console.debug('[ws] message:', Object.keys(msg))

                // Setup complete — start mic capture
                if (msg.setupComplete) {
                    console.debug('[ws] setup complete')
                    setConnectionStatus('connected')
                    setTurnStatus('idle')
                    startMicCapture()
                    return
                }

                // Handle tool calls
                if (msg.toolCall) {
                    const functionCalls: {
                        id: string
                        name: string
                        args: Record<string, unknown>
                    }[] = msg.toolCall.functionCalls ?? []
                    console.debug(
                        '[tool] received tool call:',
                        functionCalls.map((fc) => ({
                            name: fc.name,
                            args: fc.args,
                        })),
                    )

                    const functionResponses = []
                    for (const fc of functionCalls) {
                        console.debug(
                            `[tool] executing ${fc.name} with args:`,
                            fc.args,
                        )
                        setToolStatus(`Running ${fc.name}...`)
                        setTranscript((prev) => [
                            ...prev,
                            {
                                role: 'tool' as const,
                                text: `${fc.name}(${JSON.stringify(fc.args)})`,
                            },
                        ])

                        const result = await executeToolCall(
                            convexClient,
                            fc.name,
                            fc.args,
                        )
                        console.debug(`[tool] ${fc.name} result:`, result)
                        functionResponses.push({
                            id: fc.id,
                            name: fc.name,
                            response: { result },
                        })
                    }

                    console.debug(
                        '[tool] sending toolResponse:',
                        functionResponses.map((r) => r.name),
                    )
                    ws.send(
                        JSON.stringify({
                            toolResponse: { functionResponses },
                        }),
                    )
                    setToolStatus(null)
                    return
                }

                // Handle tool call cancellation
                if (msg.toolCallCancellation) {
                    console.debug(
                        '[tool] tool call cancelled:',
                        msg.toolCallCancellation,
                    )
                    setToolStatus(null)
                    return
                }

                const serverContent = msg.serverContent
                const parts = serverContent?.modelTurn?.parts
                if (parts) {
                    console.debug(
                        '[ws] model turn, parts:',
                        parts.length,
                        parts.map((p: Record<string, unknown>) =>
                            p.inlineData
                                ? 'audio'
                                : p.text
                                  ? 'text'
                                  : 'unknown',
                        ),
                    )
                    setTurnStatus('ai-speaking')
                    for (const part of parts) {
                        if (part.inlineData?.data) {
                            const float32 = base64ToPcmFloat32(
                                part.inlineData.data,
                            )
                            playbackNode.port.postMessage(float32)
                        }
                        if (part.text) {
                            setTranscript((prev) => [
                                ...prev,
                                { role: 'model', text: part.text },
                            ])
                        }
                    }
                }

                if (serverContent?.interrupted) {
                    console.debug('[ws] interrupted by user')
                    playbackNode.port.postMessage('interrupt')
                    setTurnStatus('user-speaking')
                }

                if (serverContent?.turnComplete) {
                    console.debug('[ws] turn complete')
                    setTurnStatus('idle')
                }
            }

            ws.onerror = (e) => {
                console.error('[ws] error:', e)
                setError('WebSocket connection error')
                setConnectionStatus('disconnected')
            }

            ws.onclose = (e) => {
                console.debug('[ws] closed, code:', e.code, 'reason:', e.reason)
                setConnectionStatus('disconnected')
                setTurnStatus('idle')
                setMicLevel(0)
            }
        } catch (err) {
            console.error('Failed to connect:', err)
            setError(err instanceof Error ? err.message : 'Failed to connect')
            setConnectionStatus('disconnected')
        }
    }, [startMicCapture])

    // ── Disconnect ─────────────────────────────────────────────

    const disconnect = useCallback(() => {
        captureWorkletRef.current?.disconnect()
        captureWorkletRef.current?.port.close()
        captureContextRef.current?.close()
        for (const track of mediaStreamRef.current?.getTracks() ?? []) {
            track.stop()
        }

        playbackWorkletRef.current?.disconnect()
        playbackContextRef.current?.close()

        wsRef.current?.close()

        captureWorkletRef.current = null
        captureContextRef.current = null
        mediaStreamRef.current = null
        playbackWorkletRef.current = null
        playbackContextRef.current = null
        wsRef.current = null

        setConnectionStatus('disconnected')
        setTurnStatus('idle')
        setToolStatus(null)
        setMicLevel(0)
    }, [])

    useEffect(() => disconnect, [disconnect])

    // ── Render ─────────────────────────────────────────────────

    const isConnected = connectionStatus === 'connected'
    const isConnecting = connectionStatus === 'connecting'

    const turnLabel = {
        idle: 'Listening...',
        'user-speaking': 'You are speaking',
        'ai-speaking': 'Gemini is speaking...',
    } as const

    return (
        <div className="flex min-h-screen items-center justify-center bg-background p-4">
            <Card className="w-full max-w-md">
                <CardHeader>
                    <CardTitle>Gemini Live Demo</CardTitle>
                    <CardDescription>
                        Real-time audio conversation with Gemini 3.1 Flash —
                        secured via ephemeral token
                    </CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                    {/* Connection status */}
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
                                ? 'Connected'
                                : isConnecting
                                  ? 'Requesting token...'
                                  : 'Disconnected'}
                        </span>
                    </div>

                    {/* Turn status + mic level (only when connected) */}
                    {isConnected && (
                        <div className="flex flex-col gap-2">
                            {/* Turn indicator */}
                            <div className="flex items-center gap-2">
                                <div
                                    className={`size-2 rounded-full ${
                                        toolStatus
                                            ? 'bg-yellow-500 animate-pulse'
                                            : turnStatus === 'ai-speaking'
                                              ? 'bg-blue-500 animate-pulse'
                                              : turnStatus === 'user-speaking'
                                                ? 'bg-green-500 animate-pulse'
                                                : 'bg-muted-foreground/30'
                                    }`}
                                />
                                <span className="text-sm text-muted-foreground">
                                    {toolStatus ?? turnLabel[turnStatus]}
                                </span>
                                {toolStatus && (
                                    <Wrench className="size-3.5 text-yellow-500" />
                                )}
                            </div>

                            {/* Mic level meter */}
                            <div className="flex items-center gap-2">
                                <Mic className="size-3.5 text-muted-foreground" />
                                <div className="h-2 flex-1 overflow-hidden rounded-full bg-muted">
                                    <div
                                        className="h-full rounded-full bg-green-500 transition-[width] duration-75"
                                        style={{
                                            width: `${micLevel * 100}%`,
                                        }}
                                    />
                                </div>
                            </div>
                        </div>
                    )}

                    {/* Error */}
                    {error && (
                        <p className="text-sm text-destructive">{error}</p>
                    )}

                    {/* Controls */}
                    <div className="flex gap-2">
                        {connectionStatus === 'disconnected' ? (
                            <Button onClick={connect} className="flex-1">
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

                    {/* Transcript */}
                    {transcript.length > 0 && (
                        <div className="flex max-h-48 flex-col gap-1 overflow-y-auto rounded-lg border p-3">
                            {transcript.map((entry, i) =>
                                entry.role === 'tool' ? (
                                    <ToolCallEntry key={i} text={entry.text} />
                                ) : (
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
                                ),
                            )}
                        </div>
                    )}

                    {/* Nav link */}
                    <Link
                        to="/expenses"
                        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
                    >
                        <ExternalLink className="size-3.5" />
                        View all expenses
                    </Link>
                </CardContent>
            </Card>
        </div>
    )
}

function ToolCallEntry({ text }: { text: string }) {
    const [open, setOpen] = useState(false)

    return (
        <button
            type="button"
            onClick={() => setOpen((o) => !o)}
            className="flex w-full cursor-pointer flex-col items-start gap-0.5 rounded px-1 py-0.5 text-left text-sm font-mono text-yellow-600 hover:bg-muted/50 dark:text-yellow-400"
        >
            <span className="flex items-center gap-1">
                <Wrench className="size-3 shrink-0" />
                <span className="truncate">Tool call</span>
                <ChevronDown
                    className={`size-3 shrink-0 transition-transform ${open ? 'rotate-180' : ''}`}
                />
            </span>
            {open && (
                <span className="mt-0.5 w-full break-all text-xs text-yellow-600/80 dark:text-yellow-400/80">
                    {text}
                </span>
            )}
        </button>
    )
}
