import {
    GoogleGenAI,
    type LiveServerMessage,
    type Session,
} from '@google/genai'
import { api } from '@wallet-bot/backend/api'
import { useConvex } from 'convex/react'
import { useCallback, useEffect, useRef, useState } from 'react'
import { executeToolCall } from '@/lib/agent-tools'

// ── Constants ─────────────────────────────────────────────────

const INPUT_SAMPLE_RATE = 16000
const OUTPUT_SAMPLE_RATE = 24000

// ── Audio helpers ─────────────────────────────────────────────

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

// ── Hook ──────────────────────────────────────────────────────

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected'

export interface VoiceLogEntry {
    id: number
    timestamp: Date
    type: 'info' | 'tool-call' | 'tool-response' | 'audio' | 'error'
    message: string
    detail?: unknown
}

export function useVoice() {
    const convex = useConvex()

    const [connectionStatus, setConnectionStatus] =
        useState<ConnectionStatus>('disconnected')
    const [isMuted, setIsMuted] = useState(false)
    const [micLevel, setMicLevel] = useState(0)
    const [devices, setDevices] = useState<MediaDeviceInfo[]>([])
    const [selectedDeviceId, setSelectedDeviceId] = useState<string>('')
    const [logs, setLogs] = useState<VoiceLogEntry[]>([])

    const logIdRef = useRef(0)
    const pushLog = useCallback(
        (type: VoiceLogEntry['type'], message: string, detail?: unknown) => {
            const entry: VoiceLogEntry = {
                id: ++logIdRef.current,
                timestamp: new Date(),
                type,
                message,
                detail,
            }
            setLogs((prev) => [...prev, entry])
        },
        [],
    )

    const sessionRef = useRef<Session | null>(null)
    const captureContextRef = useRef<AudioContext | null>(null)
    const captureWorkletRef = useRef<AudioWorkletNode | null>(null)
    const mediaStreamRef = useRef<MediaStream | null>(null)
    const playbackContextRef = useRef<AudioContext | null>(null)
    const playbackWorkletRef = useRef<AudioWorkletNode | null>(null)
    const isMutedRef = useRef(false)
    const selectedDeviceIdRef = useRef(selectedDeviceId)

    useEffect(() => {
        isMutedRef.current = isMuted
    }, [isMuted])

    useEffect(() => {
        selectedDeviceIdRef.current = selectedDeviceId
    }, [selectedDeviceId])

    // ── Enumerate microphones ─────────────────────────────────
    const refreshDevicesRef = useRef(async () => {
        const all = await navigator.mediaDevices.enumerateDevices()
        const mics = all.filter((d) => d.kind === 'audioinput')
        setDevices(mics)
        if (
            mics.length > 0 &&
            !mics.some((d) => d.deviceId === selectedDeviceIdRef.current)
        ) {
            setSelectedDeviceId(mics[0].deviceId)
        }
    })

    useEffect(() => {
        const handler = () => {
            refreshDevicesRef.current()
        }
        handler()
        navigator.mediaDevices.addEventListener('devicechange', handler)
        return () => {
            navigator.mediaDevices.removeEventListener('devicechange', handler)
        }
    }, [])

    // ── Mic capture (16kHz AudioWorklet) ──────────────────────
    const startMicCapture = useCallback(async (deviceId: string) => {
        const stream = await navigator.mediaDevices.getUserMedia({
            audio: {
                deviceId: deviceId ? { exact: deviceId } : undefined,
                sampleRate: INPUT_SAMPLE_RATE,
                channelCount: 1,
                echoCancellation: true,
                noiseSuppression: true,
                autoGainControl: true,
            },
        })
        mediaStreamRef.current = stream

        const captureCtx = new AudioContext({ sampleRate: INPUT_SAMPLE_RATE })
        await captureCtx.audioWorklet.addModule(
            '/audio-processors/capture.worklet.js',
        )

        const worklet = new AudioWorkletNode(
            captureCtx,
            'audio-capture-processor',
        )

        worklet.port.onmessage = (event: MessageEvent) => {
            const float32: Float32Array = event.data.data
            const rms = computeRMS(float32)
            setMicLevel(Math.min(1, rms * 10))

            if (isMutedRef.current) return
            const session = sessionRef.current
            if (!session) return

            const pcm = floatTo16BitPCM(float32)
            const base64 = arrayBufferToBase64(pcm)
            session.sendRealtimeInput({
                audio: { data: base64, mimeType: 'audio/pcm;rate=16000' },
            })
        }

        const source = captureCtx.createMediaStreamSource(stream)
        source.connect(worklet)

        captureContextRef.current = captureCtx
        captureWorkletRef.current = worklet
    }, [])

    // ── Stop mic capture ──────────────────────────────────────
    const stopMicCapture = useCallback(() => {
        captureWorkletRef.current?.disconnect()
        captureWorkletRef.current?.port.close()
        captureContextRef.current?.close()
        for (const track of mediaStreamRef.current?.getTracks() ?? []) {
            track.stop()
        }
        captureWorkletRef.current = null
        captureContextRef.current = null
        mediaStreamRef.current = null
        setMicLevel(0)
    }, [])

    // ── Switch mic while connected ────────────────────────────
    const handleDeviceChange = useCallback(
        async (deviceId: string) => {
            setSelectedDeviceId(deviceId)
            if (connectionStatus === 'connected') {
                stopMicCapture()
                await startMicCapture(deviceId)
            }
        },
        [connectionStatus, stopMicCapture, startMicCapture],
    )

    // ── Connect ───────────────────────────────────────────────
    const connect = useCallback(async () => {
        setConnectionStatus('connecting')
        pushLog('info', 'Connecting...')
        try {
            const tempStream = await navigator.mediaDevices.getUserMedia({
                audio: true,
            })
            for (const track of tempStream.getTracks()) track.stop()
            await refreshDevicesRef.current()

            pushLog('info', 'Requesting ephemeral token')
            const { token, model } = await convex.action(
                api.live.actions.requestLiveToken,
                {},
            )
            pushLog('info', `Token received, model: ${model}`)

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

            const ai = new GoogleGenAI({
                apiKey: token,
                httpOptions: { apiVersion: 'v1alpha' },
            })
            const session = await ai.live.connect({
                model: `models/${model}`,
                callbacks: {
                    onmessage: async (msg: LiveServerMessage) => {
                        if (msg.toolCall) {
                            const functionCalls =
                                msg.toolCall.functionCalls ?? []
                            for (const fc of functionCalls) {
                                pushLog('tool-call', `${fc.name}()`, fc.args)
                            }
                            const functionResponses = []
                            for (const fc of functionCalls) {
                                const result = await executeToolCall(
                                    convex,
                                    fc.name ?? '',
                                    fc.args ?? {},
                                )
                                functionResponses.push({
                                    id: fc.id,
                                    name: fc.name,
                                    response: { result },
                                })
                                pushLog(
                                    'tool-response',
                                    `${fc.name}() responded`,
                                    result,
                                )
                            }
                            session.sendToolResponse({ functionResponses })
                            return
                        }

                        if (msg.toolCallCancellation) {
                            pushLog(
                                'info',
                                'Tool call cancelled',
                                msg.toolCallCancellation.ids,
                            )
                            return
                        }

                        const parts = msg.serverContent?.modelTurn?.parts
                        if (parts) {
                            for (const part of parts) {
                                if (part.inlineData?.data) {
                                    const float32 = base64ToPcmFloat32(
                                        part.inlineData.data,
                                    )
                                    playbackNode.port.postMessage(float32)
                                }
                                if (part.text) {
                                    pushLog('info', `Model: ${part.text}`)
                                }
                            }
                        }

                        if (msg.serverContent?.interrupted) {
                            pushLog('info', 'Model interrupted')
                            playbackNode.port.postMessage('interrupt')
                        }
                    },
                    onerror: () => {
                        pushLog('error', 'WebSocket error')
                        setConnectionStatus('disconnected')
                    },
                    onclose: () => {
                        pushLog('info', 'Disconnected')
                        setConnectionStatus('disconnected')
                        setMicLevel(0)
                    },
                },
            })

            sessionRef.current = session
            setConnectionStatus('connected')
            pushLog('info', 'Connected, starting mic capture')
            await startMicCapture(selectedDeviceIdRef.current)
        } catch (err) {
            pushLog(
                'error',
                `Connection failed: ${err instanceof Error ? err.message : String(err)}`,
            )
            setConnectionStatus('disconnected')
        }
    }, [convex, startMicCapture, pushLog])

    // ── Disconnect ────────────────────────────────────────────
    const disconnect = useCallback(() => {
        stopMicCapture()
        playbackWorkletRef.current?.disconnect()
        playbackContextRef.current?.close()
        sessionRef.current?.close()
        playbackWorkletRef.current = null
        playbackContextRef.current = null
        sessionRef.current = null
        setConnectionStatus('disconnected')
        pushLog('info', 'Disconnected by user')
    }, [stopMicCapture, pushLog])

    const clearLogs = useCallback(() => setLogs([]), [])

    useEffect(() => disconnect, [disconnect])

    return {
        connectionStatus,
        isConnected: connectionStatus === 'connected',
        isConnecting: connectionStatus === 'connecting',
        isMuted,
        setIsMuted,
        micLevel,
        devices,
        selectedDeviceId,
        handleDeviceChange,
        connect,
        disconnect,
        logs,
        clearLogs,
    }
}
