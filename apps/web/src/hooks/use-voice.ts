import {
    GoogleGenAI,
    type LiveServerMessage,
    type Session,
} from '@google/genai'
import { api } from '@wallet-bot/backend/api'
import type { ToolName } from '@wallet-bot/shared'
import { useConvex, useQuery } from 'convex/react'
import { useCallback, useEffect, useRef, useState } from 'react'
import { executeToolCall } from '@/lib/agent-tools'
import type { AgentToolContext } from '@/lib/agent-tools/helpers'
import { useT } from '@/lib/i18n'
import {
    createVoiceHistoryRecorder,
    type VoiceEventDirection,
    type VoiceEventModality,
    type VoiceHistoryRecorder,
} from '@/lib/voice-history'

// Constants

const INPUT_SAMPLE_RATE = 16000
const OUTPUT_SAMPLE_RATE = 24000

/**
 * Whether the model's spoken answer is played back when the user's turn was
 * *typed*. Hardcoded for now, mirroring `_kRespondToTextWithAudio` in
 * `apps/native/lib/screens/voice.dart`; future work will expose it as a user
 * preference.
 *
 * The session is always negotiated with `responseModalities: [AUDIO]` (the
 * ephemeral token bakes that in — see `convex/live/createToken.ts`), so the
 * transcript is always rendered and "text-only" means *audio suppressed at
 * playback*, never a different server config. The rules, matching native:
 *
 * - user turn sent as audio  → transcript + audible reply;
 * - user turn sent as text   → transcript only, no playback;
 * - session started by text  → starts suppressed;
 * - user speaks again        → playback re-enabled for that turn onward;
 * - server `interrupted`     → discard queued output until `turnComplete`.
 */
const RESPOND_TO_TEXT_WITH_AUDIO = false

/** Which interaction opened the session — it decides the reply modality. */
export type SessionMode = 'audio' | 'text'

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
    const [isMicCaptureActive, setIsMicCaptureActive] = useState(false)
    const [isMicOn, setIsMicOn] = useState(false)
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
    const selectedDeviceIdRef = useRef(selectedDeviceId)

    // Mirrors of the state above, so the audio callbacks and the message
    // handler read the live value instead of the one captured at render.
    const statusRef = useRef<ConnectionStatus>('disconnected')
    const micCaptureActiveRef = useRef(false)
    const micOnRef = useRef(false)
    const micOpeningRef = useRef(false)
    const composingRef = useRef(false)

    // Reply-modality state — see RESPOND_TO_TEXT_WITH_AUDIO above.
    const audioPlaybackEnabledRef = useRef(true)
    const discardOutputRef = useRef(false)
    const audioStreamOpenRef = useRef(false)
    const pendingTextRef = useRef<string[]>([])

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
        selectedDeviceIdRef.current = selectedDeviceId
    }, [selectedDeviceId])

    const applyStatus = useCallback((next: ConnectionStatus) => {
        statusRef.current = next
        setConnectionStatus(next)
    }, [])

    // Voice history replication. The recorder lives for one session and is
    // best-effort: see `@/lib/voice-history`. `ownerId` comes from the server
    // because `appendEvents` rejects a batch whose owner is not the
    // authenticated user, and a guessed id would throw that batch away.
    const ownerId = useQuery(api.v1.users.queries.getMyId) ?? null
    const ownerIdRef = useRef(ownerId)
    const historyRef = useRef<VoiceHistoryRecorder | null>(null)

    useEffect(() => {
        ownerIdRef.current = ownerId
    }, [ownerId])

    const recordHistory = useCallback(
        (
            type: string,
            direction: VoiceEventDirection,
            payload?: Record<string, unknown>,
            modality?: VoiceEventModality,
        ) => {
            historyRef.current?.record(type, direction, payload, modality)
        },
        [],
    )

    /**
     * Native's `send_message` client action (`sendText`). A typed turn has no
     * input transcription, so this is the only record of what the user said.
     */
    const recordSendMessage = useCallback(
        (text: string) => {
            recordHistory(
                'send_message',
                'client',
                { interactionModality: 'text', text },
                'text',
            )
        },
        [recordHistory],
    )

    /** Native's `_recordMuteEvent`, with the same five details. */
    const recordMute = useCallback(
        (reason: string) => {
            recordHistory('mute_changed', 'client', {
                muted: !micOnRef.current || composingRef.current,
                reason,
                micCaptureActive: micCaptureActiveRef.current,
                userMicOn: micOnRef.current,
                textComposing: composingRef.current,
            })
        },
        [recordHistory],
    )

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
            recordHistory(
                'user_transcript_delta',
                'server',
                { text: chunk },
                'voice',
            )
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
        [finalisePendingAgent, nextId, recordHistory],
    )

    const appendAgent = useCallback(
        (chunk: string) => {
            recordHistory(
                'agent_transcript_delta',
                'server',
                { text: chunk },
                'voice',
            )
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
        [finalisePendingUser, nextId, recordHistory],
    )

    /** A typed turn has no input transcription — echo it locally instead. */
    const appendTypedUser = useCallback(
        (text: string) => {
            finalisePendingUser()
            finalisePendingAgent()
            setMessages((prev) => [
                ...prev,
                {
                    kind: 'user',
                    id: nextId(),
                    at: new Date(),
                    text,
                    isFinal: true,
                },
            ])
        },
        [finalisePendingUser, finalisePendingAgent, nextId],
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

    /**
     * Tell the server the audio turn is over. Sent when the mic goes away, is
     * muted, or the user starts typing: chunks stop flowing on our side
     * immediately, but the server still holds whatever it buffered for the
     * turn. Only meaningful while a stream is actually open.
     */
    const endAudioStream = useCallback(() => {
        if (!audioStreamOpenRef.current) return
        audioStreamOpenRef.current = false
        sessionRef.current?.sendRealtimeInput({ audioStreamEnd: true })
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
            // Muted covers all three native conditions: capture off, user mic
            // off, or the user is composing text (`_isMicEffectivelyMuted`).
            const muted = !micOnRef.current || composingRef.current
            setMicLevel(muted ? 0 : Math.min(1, computeRMS(float32) * 10))
            if (muted) return

            const session = sessionRef.current
            if (!session) return

            const pcm = floatTo16BitPCM(float32)
            const base64 = arrayBufferToBase64(pcm)
            audioStreamOpenRef.current = true
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
        micCaptureActiveRef.current = false
        micOnRef.current = false
        setIsMicCaptureActive(false)
        setIsMicOn(false)
        setMicLevel(0)
        recordHistory('mic_capture_stopped', 'client', { muted: true })
    }, [recordHistory])

    /** Turn the user's mic on or off without tearing capture down. */
    const setMicOn = useCallback(
        (on: boolean) => {
            micOnRef.current = on
            setIsMicOn(on)
            recordMute(on ? 'tap_unmute' : 'tap_mute')
            if (on) return
            setMicLevel(0)
            endAudioStream()
        },
        [endAudioStream, recordMute],
    )

    /** Open the mic — prompts for permission the first time. */
    const openMic = useCallback(
        async ({ turnOn }: { turnOn: boolean } = { turnOn: true }) => {
            if (micCaptureActiveRef.current) {
                if (turnOn) setMicOn(true)
                return
            }
            if (micOpeningRef.current) return
            micOpeningRef.current = true
            try {
                await startMicCapture(selectedDeviceIdRef.current)
                // Device labels are only exposed once permission is granted.
                await refreshDevicesRef.current()
                micCaptureActiveRef.current = true
                setIsMicCaptureActive(true)
                setMicOn(turnOn)
                recordMute('mic_capture_started')
            } catch (err) {
                stopMicCapture()
                const message = catalog.voice.systemMicOpenFailed({
                    error: err instanceof Error ? err.message : String(err),
                })
                addSystem(message, 'error')
                recordHistory('error', 'local', {
                    message,
                    isTransient: false,
                })
            }
            // Cleared on both paths — `finally` would stop the React Compiler
            // from lowering this hook (`react-hooks/todo`).
            micOpeningRef.current = false
        },
        [
            startMicCapture,
            stopMicCapture,
            setMicOn,
            addSystem,
            catalog,
            recordMute,
            recordHistory,
        ],
    )

    // Switch mic while connected
    const handleDeviceChange = useCallback(
        async (deviceId: string) => {
            setSelectedDeviceId(deviceId)
            selectedDeviceIdRef.current = deviceId
            if (!micCaptureActiveRef.current) return
            const wasOn = micOnRef.current
            endAudioStream()
            stopMicCapture()
            await openMic({ turnOn: wasOn })
        },
        [endAudioStream, stopMicCapture, openMic],
    )

    /**
     * Release the playback pipeline. Every path that ends a session must run
     * this — audio contexts are a limited OS resource, and a failed connect or
     * a server-side close used to leak one per attempt.
     */
    const stopPlayback = useCallback(() => {
        playbackWorkletRef.current?.disconnect()
        playbackContextRef.current?.close()
        playbackWorkletRef.current = null
        playbackContextRef.current = null
    }, [])

    /** Send the turns typed before the session was up, in order. */
    const flushPendingText = useCallback(() => {
        const queued = pendingTextRef.current
        pendingTextRef.current = []
        const session = sessionRef.current
        if (!session || queued.length === 0) return
        // These are typed turns, so they follow the text reply rule.
        audioPlaybackEnabledRef.current = RESPOND_TO_TEXT_WITH_AUDIO
        for (const text of queued) {
            session.sendClientContent({
                turns: [{ role: 'user', parts: [{ text }] }],
                turnComplete: true,
            })
        }
    }, [])

    // Connect
    const connect = useCallback(
        async (mode: SessionMode = 'audio') => {
            if (statusRef.current !== 'disconnected') return
            applyStatus('connecting')
            pendingUserIdRef.current = null
            pendingAgentIdRef.current = null
            audioStreamOpenRef.current = false
            discardOutputRef.current = false
            audioPlaybackEnabledRef.current =
                mode === 'audio' ? true : RESPOND_TO_TEXT_WITH_AUDIO
            addSystem(catalog.voice.systemConnecting, 'info')

            // One recorder per session, created before the first await so a
            // turn typed while connecting still lands in the same history.
            historyRef.current = createVoiceHistoryRecorder(
                convex,
                () => ownerIdRef.current,
            )
            recordHistory('connecting', 'local', {
                message: catalog.voice.systemConnecting,
            })

            try {
                const { token, model } = await convex.action(
                    api.v1.live.actions.requestLiveToken,
                    {},
                )
                const tokenNotice = catalog.voice.systemTokenReceived({ model })
                addSystem(tokenNotice, 'info')
                // The model is only known now, so this is where the session row
                // becomes uploadable.
                historyRef.current?.open(model)
                recordHistory('system', 'local', { message: tokenNotice })

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
                                    response: {
                                        result: Record<string, unknown>
                                    }
                                }[] = []
                                for (const fc of functionCalls) {
                                    addToolCall(
                                        fc.id ?? '',
                                        fc.name ?? '',
                                        (fc.args ?? {}) as Record<
                                            string,
                                            unknown
                                        >,
                                    )
                                    recordHistory(
                                        'tool_call',
                                        'server',
                                        {
                                            id: fc.id ?? '',
                                            name: fc.name ?? '',
                                            args: fc.args ?? {},
                                        },
                                        'tool',
                                    )
                                }
                                for (const fc of functionCalls) {
                                    const result = await executeToolCall(
                                        optsRef.current.context,
                                        fc.name ?? '',
                                        (fc.args ?? {}) as Record<
                                            string,
                                            unknown
                                        >,
                                    )
                                    completeToolCall(fc.id ?? '', result)
                                    recordHistory(
                                        'tool_result',
                                        'client',
                                        {
                                            id: fc.id ?? '',
                                            name: fc.name ?? '',
                                            result,
                                        },
                                        'tool',
                                    )
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
                                ).filter(
                                    (x): x is string => typeof x === 'string',
                                )
                                cancelToolCalls(ids)
                                recordHistory(
                                    'tool_cancelled',
                                    'server',
                                    { ids },
                                    'tool',
                                )
                                return
                            }

                            if (msg.usageMetadata) {
                                recordHistory('usage_metadata', 'server', {
                                    ...msg.usageMetadata,
                                })
                            }
                            if (msg.goAway) {
                                recordHistory('go_away', 'server', {
                                    timeLeft: msg.goAway.timeLeft,
                                })
                            }
                            if (msg.sessionResumptionUpdate) {
                                // Only the two booleans, never the handle —
                                // native redacts it from the wire as well.
                                recordHistory(
                                    'session_resumption_update',
                                    'server',
                                    {
                                        resumable:
                                            msg.sessionResumptionUpdate
                                                .resumable ?? false,
                                        hasNewHandle: Boolean(
                                            msg.sessionResumptionUpdate
                                                .newHandle,
                                        ),
                                    },
                                )
                            }

                            const sc = msg.serverContent
                            if (!sc) return

                            const inputText = sc.inputTranscription?.text
                            if (inputText) {
                                // The user spoke: a typed turn silenced
                                // playback, a spoken one makes the reply
                                // audible again.
                                audioPlaybackEnabledRef.current = true
                                discardOutputRef.current = false
                                appendUser(inputText)
                            }

                            const outputText = sc.outputTranscription?.text
                            if (outputText) appendAgent(outputText)

                            if (sc.interrupted) {
                                recordHistory('agent_interrupted', 'server', {
                                    reason: 'server_interrupted',
                                })
                                discardOutputRef.current = true
                                playbackNode.port.postMessage('interrupt')
                                finalisePendingAgent({ interrupted: true })
                            }

                            const parts = sc.modelTurn?.parts
                            if (parts) {
                                const playable =
                                    audioPlaybackEnabledRef.current &&
                                    !discardOutputRef.current
                                for (const part of parts) {
                                    if (playable && part.inlineData?.data) {
                                        playbackNode.port.postMessage(
                                            base64ToPcmFloat32(
                                                part.inlineData.data,
                                            ),
                                        )
                                    }
                                    if (part.text) {
                                        appendAgent(part.text)
                                    }
                                }
                            }

                            if (sc.turnComplete) {
                                recordHistory('agent_turn_complete', 'server')
                                discardOutputRef.current = false
                                finalisePendingAgent()
                            }
                        },
                        onerror: () => {
                            addSystem(catalog.voice.systemSocketError, 'error')
                            recordHistory('error', 'local', {
                                message: catalog.voice.systemSocketError,
                                isTransient: true,
                            })
                            applyStatus('disconnected')
                        },
                        onclose: (event: CloseEvent) => {
                            addSystem(catalog.voice.systemDisconnected, 'info')
                            recordHistory('disconnected', 'server', {
                                code: event.code,
                                reason: event.reason,
                            })
                            applyStatus('disconnected')
                            audioStreamOpenRef.current = false
                            pendingTextRef.current = []
                            sessionRef.current = null
                            // The socket is gone: release the mic instead of
                            // capturing into a dead session (the control bar
                            // would still show a live mic otherwise).
                            stopMicCapture()
                            stopPlayback()
                            finalisePendingUser()
                            finalisePendingAgent()
                            // No resumption on web yet (backlog 1.5), so a
                            // closed socket ends the session for good.
                            historyRef.current?.end({ explicit: false })
                        },
                    },
                })

                sessionRef.current = session
                applyStatus('connected')
                historyRef.current?.markStatus('active')
                recordHistory('connected', 'local')
                addSystem(
                    mode === 'audio'
                        ? catalog.voice.systemConnected
                        : catalog.voice.systemConnectedTyping,
                    'success',
                )
                flushPendingText()
                if (mode === 'audio') await openMic({ turnOn: true })
            } catch (err) {
                pendingTextRef.current = []
                stopPlayback()
                const message = catalog.voice.systemConnectionFailed({
                    error: err instanceof Error ? err.message : String(err),
                })
                addSystem(message, 'error')
                recordHistory('error', 'local', {
                    message,
                    isTransient: false,
                })
                historyRef.current?.end({ explicit: false })
                applyStatus('disconnected')
            }
        },
        [
            convex,
            catalog,
            applyStatus,
            openMic,
            stopMicCapture,
            stopPlayback,
            flushPendingText,
            addSystem,
            addToolCall,
            completeToolCall,
            cancelToolCalls,
            appendUser,
            appendAgent,
            finalisePendingUser,
            finalisePendingAgent,
            recordHistory,
        ],
    )

    /**
     * Send a typed turn. With no session yet it starts one in text mode and
     * replays the message once connected; mid-session it flushes any open
     * audio turn first, exactly like native's `sendText`.
     */
    const sendText = useCallback(
        (raw: string) => {
            const text = raw.trim()
            if (!text) return
            const status = statusRef.current

            if (status === 'connected') {
                appendTypedUser(text)
                recordSendMessage(text)
                audioPlaybackEnabledRef.current = RESPOND_TO_TEXT_WITH_AUDIO
                endAudioStream()
                sessionRef.current?.sendClientContent({
                    turns: [{ role: 'user', parts: [{ text }] }],
                    turnComplete: true,
                })
                return
            }

            if (status === 'disconnected') {
                setMessages([])
                appendTypedUser(text)
                pendingTextRef.current = [...pendingTextRef.current, text]
                // `connect` runs synchronously until its first await, so the
                // recorder exists by the time it returns and the turn is
                // recorded after the `connecting` notice, in the right order.
                void connect('text')
                recordSendMessage(text)
                return
            }

            appendTypedUser(text)
            pendingTextRef.current = [...pendingTextRef.current, text]
            recordSendMessage(text)
        },
        [appendTypedUser, endAudioStream, connect, recordSendMessage],
    )

    /**
     * Track whether the composer holds text. Typing mutes the mic (native's
     * `_isTextComposing`) and, on the transition into composing, flushes the
     * audio turn the server is still buffering.
     */
    const setComposing = useCallback(
        (composing: boolean) => {
            const started = composing && !composingRef.current
            composingRef.current = composing
            if (started) recordMute('text_composing')
            if (composing) setMicLevel(0)
            if (
                started &&
                statusRef.current === 'connected' &&
                micCaptureActiveRef.current
            ) {
                endAudioStream()
            }
        },
        [endAudioStream, recordMute],
    )

    // Disconnect
    const disconnect = useCallback(() => {
        recordHistory('end_session', 'client')
        endAudioStream()
        stopMicCapture()
        stopPlayback()
        sessionRef.current?.close()
        sessionRef.current = null
        audioStreamOpenRef.current = false
        pendingTextRef.current = []
        discardOutputRef.current = false
        audioPlaybackEnabledRef.current = true
        applyStatus('disconnected')
        finalisePendingUser()
        finalisePendingAgent()
        // Ends the row and flushes the tail, native's `endExplicitly` + flush.
        historyRef.current?.end({ explicit: true })
    }, [
        endAudioStream,
        stopMicCapture,
        stopPlayback,
        applyStatus,
        finalisePendingUser,
        finalisePendingAgent,
        recordHistory,
    ])

    const clearMessages = useCallback(() => setMessages([]), [])

    useEffect(() => disconnect, [disconnect])

    return {
        connectionStatus,
        isConnected: connectionStatus === 'connected',
        isConnecting: connectionStatus === 'connecting',
        /** Capture is running (the browser gave us the mic). */
        isMicCaptureActive,
        /** The user has the mic on — the tap/push-to-talk toggle. */
        isMicOn,
        micLevel,
        devices,
        selectedDeviceId,
        handleDeviceChange,
        connect,
        disconnect,
        openMic,
        setMicOn,
        sendText,
        setComposing,
        messages,
        clearMessages,
    }
}
