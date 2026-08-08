import {
    GoogleGenAI,
    type LiveServerMessage,
    type Session,
} from '@google/genai'
import { api } from '@wallet-bot/backend/api'
import type { ToolName } from '@wallet-bot/shared'
import { useConvex } from 'convex/react'
import { useCallback, useEffect, useRef, useState } from 'react'
import { executeToolCall } from '@/lib/agent-tools'
import type { AgentToolContext } from '@/lib/agent-tools/helpers'
import { useT } from '@/lib/i18n'

// Constants

const INPUT_SAMPLE_RATE = 16000
const OUTPUT_SAMPLE_RATE = 24000

// Audio helpers

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

// Chat message model

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected'

export type ToolStatus = 'pending' | 'completed' | 'cancelled'

export type SystemLevel = 'info' | 'success' | 'error'

export const EDITABLE_TOOL_NAMES = [
    'addExpense',
    'addIncome',
    'addTransfer',
    'addBalanceAdjustment',
    'createAccount',
    'updateAccount',
    'createCategory',
    'updateCategory',
    'createTag',
    'updateTag',
    'updateTransaction',
] as const satisfies readonly ToolName[]

export type EditableToolName = (typeof EDITABLE_TOOL_NAMES)[number]

function isEditableTool(name: string): name is EditableToolName {
    return (EDITABLE_TOOL_NAMES as readonly string[]).includes(name)
}

export type ChatMessage =
    | {
          kind: 'user'
          id: string
          at: Date
          text: string
          isFinal: boolean
      }
    | {
          kind: 'agent'
          id: string
          at: Date
          text: string
          isFinal: boolean
          wasInterrupted: boolean
      }
    | {
          kind: 'tool'
          id: string
          at: Date
          callId: string
          name: string
          args: Record<string, unknown>
          result?: Record<string, unknown>
          status: ToolStatus
      }
    | {
          kind: 'system'
          id: string
          at: Date
          message: string
          level: SystemLevel
      }
    | {
          kind: 'action-result'
          id: string
          at: Date
          toolName: EditableToolName
          entityId: string
      }

// Hook

export type UseVoiceOpts = {
    context: AgentToolContext
}

export function useVoice(opts: UseVoiceOpts) {
    const convex = useConvex()
    const catalog = useT()

    const [connectionStatus, setConnectionStatus] =
        useState<ConnectionStatus>('disconnected')
    const [isMuted, setIsMuted] = useState(false)
    const [micLevel, setMicLevel] = useState(0)
    const [devices, setDevices] = useState<MediaDeviceInfo[]>([])
    const [selectedDeviceId, setSelectedDeviceId] = useState<string>('')
    const [messages, setMessages] = useState<ChatMessage[]>([])

    const optsRef = useRef(opts)
    // eslint-disable-next-line react-hooks/refs
    optsRef.current = opts

    const sessionRef = useRef<Session | null>(null)
    const captureContextRef = useRef<AudioContext | null>(null)
    const captureWorkletRef = useRef<AudioWorkletNode | null>(null)
    const mediaStreamRef = useRef<MediaStream | null>(null)
    const playbackContextRef = useRef<AudioContext | null>(null)
    const playbackWorkletRef = useRef<AudioWorkletNode | null>(null)
    const isMutedRef = useRef(false)
    const selectedDeviceIdRef = useRef(selectedDeviceId)

    // Aggregation state — refs so message handlers can mutate without
    // re-creating the onmessage callback on every render.
    const pendingUserIdRef = useRef<string | null>(null)
    const pendingAgentIdRef = useRef<string | null>(null)
    const idCounterRef = useRef(0)
    const nextId = useCallback(
        () => `m${++idCounterRef.current}_${Date.now()}`,
        [],
    )

    useEffect(() => {
        isMutedRef.current = isMuted
    }, [isMuted])

    useEffect(() => {
        selectedDeviceIdRef.current = selectedDeviceId
    }, [selectedDeviceId])

    // Chat message helpers

    const addSystem = useCallback(
        (message: string, level: SystemLevel = 'info') => {
            setMessages((prev) => [
                ...prev,
                {
                    kind: 'system',
                    id: nextId(),
                    at: new Date(),
                    message,
                    level,
                },
            ])
        },
        [nextId],
    )

    const finalisePendingUser = useCallback(() => {
        const pendingId = pendingUserIdRef.current
        if (!pendingId) return
        pendingUserIdRef.current = null
        setMessages((prev) =>
            prev.map((m) =>
                m.id === pendingId && m.kind === 'user'
                    ? { ...m, isFinal: true }
                    : m,
            ),
        )
    }, [])

    const finalisePendingAgent = useCallback(
        (opts?: { interrupted?: boolean }) => {
            const pendingId = pendingAgentIdRef.current
            if (!pendingId) return
            pendingAgentIdRef.current = null
            setMessages((prev) =>
                prev.map((m) =>
                    m.id === pendingId && m.kind === 'agent'
                        ? {
                              ...m,
                              isFinal: true,
                              wasInterrupted:
                                  m.wasInterrupted || !!opts?.interrupted,
                          }
                        : m,
                ),
            )
        },
        [],
    )

    const appendUser = useCallback(
        (chunk: string) => {
            finalisePendingAgent()
            if (pendingUserIdRef.current) {
                const id = pendingUserIdRef.current
                setMessages((prev) =>
                    prev.map((m) =>
                        m.id === id && m.kind === 'user'
                            ? { ...m, text: m.text + chunk }
                            : m,
                    ),
                )
                return
            }
            const id = nextId()
            pendingUserIdRef.current = id
            setMessages((prev) => [
                ...prev,
                {
                    kind: 'user',
                    id,
                    at: new Date(),
                    text: chunk,
                    isFinal: false,
                },
            ])
        },
        [finalisePendingAgent, nextId],
    )

    const appendAgent = useCallback(
        (chunk: string) => {
            finalisePendingUser()
            if (pendingAgentIdRef.current) {
                const id = pendingAgentIdRef.current
                setMessages((prev) =>
                    prev.map((m) =>
                        m.id === id && m.kind === 'agent'
                            ? { ...m, text: m.text + chunk }
                            : m,
                    ),
                )
                return
            }
            const id = nextId()
            pendingAgentIdRef.current = id
            setMessages((prev) => [
                ...prev,
                {
                    kind: 'agent',
                    id,
                    at: new Date(),
                    text: chunk,
                    isFinal: false,
                    wasInterrupted: false,
                },
            ])
        },
        [finalisePendingUser, nextId],
    )

    const addToolCall = useCallback(
        (
            callId: string,
            name: string,
            args: Record<string, unknown>,
        ): string => {
            finalisePendingUser()
            finalisePendingAgent()
            const id = nextId()
            setMessages((prev) => [
                ...prev,
                {
                    kind: 'tool',
                    id,
                    at: new Date(),
                    callId,
                    name,
                    args,
                    status: 'pending',
                },
            ])
            return id
        },
        [finalisePendingUser, finalisePendingAgent, nextId],
    )

    const completeToolCall = useCallback(
        (callId: string, result: Record<string, unknown>) => {
            setMessages((prev) => {
                const toolMsg = prev.find(
                    (m): m is Extract<ChatMessage, { kind: 'tool' }> =>
                        m.kind === 'tool' && m.callId === callId,
                )
                const updated = prev.map((m) =>
                    m.kind === 'tool' && m.callId === callId
                        ? { ...m, result, status: 'completed' as const }
                        : m,
                )
                if (
                    toolMsg &&
                    toolMsg.status === 'pending' &&
                    isEditableTool(toolMsg.name) &&
                    result.ok === true &&
                    typeof result.id === 'string'
                ) {
                    return [
                        ...updated,
                        {
                            kind: 'action-result' as const,
                            id: nextId(),
                            at: new Date(),
                            toolName: toolMsg.name,
                            entityId: result.id,
                        },
                    ]
                }
                return updated
            })
        },
        [nextId],
    )

    const cancelToolCalls = useCallback((callIds: string[]) => {
        const set = new Set(callIds)
        setMessages((prev) =>
            prev.map((m) =>
                m.kind === 'tool' && set.has(m.callId)
                    ? { ...m, status: 'cancelled' }
                    : m,
            ),
        )
    }, [])

    // Enumerate microphones
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

    // Mic capture (16kHz AudioWorklet)
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

    // Stop mic capture
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

    // Switch mic while connected
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

    // Connect
    const connect = useCallback(async () => {
        setMessages([])
        pendingUserIdRef.current = null
        pendingAgentIdRef.current = null
        setConnectionStatus('connecting')
        addSystem(catalog.voice.systemConnecting, 'info')

        try {
            const tempStream = await navigator.mediaDevices.getUserMedia({
                audio: true,
            })
            for (const track of tempStream.getTracks()) track.stop()
            await refreshDevicesRef.current()

            const { token, model } = await convex.action(
                api.v1.live.actions.requestLiveToken,
                {},
            )
            addSystem(catalog.voice.systemTokenReceived({ model }), 'info')

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
                            const functionResponses: {
                                id?: string
                                name?: string
                                response: { result: Record<string, unknown> }
                            }[] = []
                            for (const fc of functionCalls) {
                                addToolCall(
                                    fc.id ?? '',
                                    fc.name ?? '',
                                    (fc.args ?? {}) as Record<string, unknown>,
                                )
                            }
                            for (const fc of functionCalls) {
                                const result = await executeToolCall(
                                    optsRef.current.context,
                                    fc.name ?? '',
                                    (fc.args ?? {}) as Record<string, unknown>,
                                )
                                completeToolCall(fc.id ?? '', result)
                                functionResponses.push({
                                    id: fc.id,
                                    name: fc.name,
                                    response: { result },
                                })
                            }
                            session.sendToolResponse({ functionResponses })
                            return
                        }

                        if (msg.toolCallCancellation) {
                            const ids = (
                                msg.toolCallCancellation.ids ?? []
                            ).filter((x): x is string => typeof x === 'string')
                            cancelToolCalls(ids)
                            return
                        }

                        const sc = msg.serverContent
                        if (!sc) return

                        const inputText = sc.inputTranscription?.text
                        if (inputText) appendUser(inputText)

                        const outputText = sc.outputTranscription?.text
                        if (outputText) appendAgent(outputText)

                        if (sc.interrupted) {
                            playbackNode.port.postMessage('interrupt')
                            finalisePendingAgent({ interrupted: true })
                        }

                        const parts = sc.modelTurn?.parts
                        if (parts) {
                            for (const part of parts) {
                                if (part.inlineData?.data) {
                                    const float32 = base64ToPcmFloat32(
                                        part.inlineData.data,
                                    )
                                    playbackNode.port.postMessage(float32)
                                }
                                if (part.text) {
                                    appendAgent(part.text)
                                }
                            }
                        }

                        if (sc.turnComplete) {
                            finalisePendingAgent()
                        }
                    },
                    onerror: () => {
                        addSystem(catalog.voice.systemSocketError, 'error')
                        setConnectionStatus('disconnected')
                    },
                    onclose: () => {
                        addSystem(catalog.voice.systemDisconnected, 'info')
                        setConnectionStatus('disconnected')
                        setMicLevel(0)
                        finalisePendingUser()
                        finalisePendingAgent()
                    },
                },
            })

            sessionRef.current = session
            setConnectionStatus('connected')
            addSystem(catalog.voice.systemConnected, 'success')
            await startMicCapture(selectedDeviceIdRef.current)
        } catch (err) {
            addSystem(
                catalog.voice.systemConnectionFailed({
                    error: err instanceof Error ? err.message : String(err),
                }),
                'error',
            )
            setConnectionStatus('disconnected')
        }
    }, [
        convex,
        catalog,
        startMicCapture,
        addSystem,
        addToolCall,
        completeToolCall,
        cancelToolCalls,
        appendUser,
        appendAgent,
        finalisePendingUser,
        finalisePendingAgent,
    ])

    // Disconnect
    const disconnect = useCallback(() => {
        stopMicCapture()
        playbackWorkletRef.current?.disconnect()
        playbackContextRef.current?.close()
        sessionRef.current?.close()
        playbackWorkletRef.current = null
        playbackContextRef.current = null
        sessionRef.current = null
        setConnectionStatus('disconnected')
        finalisePendingUser()
        finalisePendingAgent()
    }, [stopMicCapture, finalisePendingUser, finalisePendingAgent])

    const clearMessages = useCallback(() => setMessages([]), [])

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
        messages,
        clearMessages,
    }
}
