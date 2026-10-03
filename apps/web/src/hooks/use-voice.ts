import type { LiveServerMessage } from '@google/genai'
import { api } from '@wallet-bot/backend/api'
import type { ToolName } from '@wallet-bot/shared'
import { useConvex, useQuery } from 'convex/react'
import { useCallback, useEffect, useRef, useState } from 'react'
import type { LiveTokenMintArgs } from '@/lib/agent-context'
import {
    AgentSessionCostTracker,
    recordAgentSessionCost,
    recordAgentSessionStarted,
} from '@/lib/agent-metrics'
import { executeToolCall } from '@/lib/agent-tools'
import type { AgentToolContext } from '@/lib/agent-tools/helpers'
import {
    connectGeminiLive,
    type LiveSession,
    WEB_LIVE_VERSION,
} from '@/lib/gemini-live'
import { useT } from '@/lib/i18n'
import {
    readMicrophonePreference,
    writeMicrophonePreference,
} from '@/lib/microphone-preference'
import {
    captureMicrophone,
    microphonePcm,
    VoicePlayback,
} from '@/lib/voice-audio'
import {
    createVoiceHistoryRecorder,
    type VoiceEventDirection,
    type VoiceEventModality,
    type VoiceHistoryRecorder,
} from '@/lib/voice-history'
import {
    buildConversationSeed,
    type ConversationEvent,
    parseGoogleDuration,
} from '@/lib/voice-seed'

// Constants

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
          /** The user reported this response. Set by `markReported`. */
          reported?: boolean
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
    /**
     * Builds the mint request for `requestLiveToken`: platform identity, the
     * user's locale/timezone and the USER_CONTEXT snapshot. Assembled in
     * `VoiceProvider`, where the auth/i18n contexts are all available.
     * Best-effort: when it rejects, the session connects with a bare mint.
     */
    buildMintArgs?: () => Promise<LiveTokenMintArgs>
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
    const [selectedDeviceId, setSelectedDeviceId] = useState<string>(
        readMicrophonePreference,
    )
    const [messages, setMessages] = useState<ChatMessage[]>([])

    const optsRef = useRef(opts)
    // eslint-disable-next-line react-hooks/refs
    optsRef.current = opts

    const sessionRef = useRef<LiveSession | null>(null)
    const connectAbortRef = useRef<AbortController | null>(null)
    const toolsSettledRef = useRef<Promise<void>>(Promise.resolve())
    const micAbortRef = useRef<AbortController | null>(null)
    const microphoneRef = useRef<{ stop: () => void } | null>(null)
    const playbackRef = useRef(new VoicePlayback())
    const startupAudioRef = useRef<{
        chunks: string[]
        samples: number
    } | null>(null)
    const selectedDeviceIdRef = useRef(selectedDeviceId)

    // Mirrors of the state above, so the audio callbacks and the message
    // handler read the live value instead of the one captured at render.
    const statusRef = useRef<ConnectionStatus>('disconnected')
    const micCaptureActiveRef = useRef(false)
    const micOnRef = useRef(false)
    const composingRef = useRef(false)

    // Reply-modality state — see RESPOND_TO_TEXT_WITH_AUDIO above.
    const audioPlaybackEnabledRef = useRef(true)
    const discardOutputRef = useRef(false)
    const audioStreamOpenRef = useRef(false)
    const pendingTextRef = useRef<string[]>([])

    // Reconnection state, porting native's design
    // (apps/native/lib/voice/gemini_voice_expense_command.dart):
    // - `sessionActiveRef` is the logical session: true from the user starting
    //   a conversation until the explicit End (or the account unmounting).
    //   A dropped socket does NOT end it — it schedules a reconnect.
    // - `generationRef` guards against late callbacks from superseded sockets.
    // - `conversationLogRef` is the in-memory event log the reconnect seed is
    //   built from (`buildConversationSeed`), web's substrate for what native
    //   reads back from its durable Drift log.
    const sessionActiveRef = useRef(false)
    const sessionModeRef = useRef<SessionMode>('audio')
    const generationRef = useRef(0)
    const reconnectAttemptRef = useRef(0)
    const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
    const goAwayTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
    const conversationLogRef = useRef<ConversationEvent[]>([])
    const connectAttemptRef = useRef<() => Promise<void>>(async () => {})

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
    /** The model the current token was minted for, once it is known. */
    const modelRef = useRef<string | null>(null)
    const sessionStartedMetricSentRef = useRef(false)
    const sessionCostMetricSentRef = useRef(false)
    const sessionCostTrackerRef = useRef(new AgentSessionCostTracker())

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
            conversationLogRef.current.push({ type: 'send_message', text })
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
            conversationLogRef.current.push({
                type: 'user_transcript_delta',
                text: chunk,
            })
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
            conversationLogRef.current.push({
                type: 'agent_transcript_delta',
                text: chunk,
            })
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
            mics.some((d) => d.deviceId.length > 0) &&
            !mics.some((d) => d.deviceId === selectedDeviceIdRef.current)
        ) {
            setSelectedDeviceId(mics[0].deviceId)
        }
    })

    useEffect(() => {
        const handler = () => {
            void refreshDevicesRef.current().catch(() => {})
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

    // Stop mic capture
    const stopMicCapture = useCallback(() => {
        startupAudioRef.current = null
        micAbortRef.current?.abort()
        microphoneRef.current?.stop()
        microphoneRef.current = null
        micCaptureActiveRef.current = false
        micOnRef.current = false
        setIsMicCaptureActive(false)
        setIsMicOn(false)
        setMicLevel(0)
        recordHistory('mic_capture_stopped', 'client', { muted: true })
    }, [recordHistory])

    /** Muting releases the browser's microphone indicator and hardware. */
    const setMicOn = useCallback(
        (on: boolean) => {
            micOnRef.current = on
            setIsMicOn(on)
            recordMute(on ? 'tap_unmute' : 'tap_mute')
            if (on) return
            setMicLevel(0)
            endAudioStream()
            stopMicCapture()
        },
        [endAudioStream, recordMute, stopMicCapture],
    )

    /** Open the mic — prompts for permission the first time. */
    const openMic = useCallback(
        async ({ turnOn }: { turnOn: boolean } = { turnOn: true }) => {
            if (micCaptureActiveRef.current) {
                if (turnOn) setMicOn(true)
                return
            }
            if (micAbortRef.current && !micAbortRef.current.signal.aborted)
                return
            const controller = new AbortController()
            micAbortRef.current = controller
            try {
                // Resume playback during the gesture, before network/permission waits.
                await playbackRef.current.open()
                controller.signal.throwIfAborted()
                const microphone = await captureMicrophone({
                    deviceId: selectedDeviceIdRef.current,
                    signal: controller.signal,
                    onAudio: (samples) => {
                        if (
                            controller.signal.aborted ||
                            !micOnRef.current ||
                            composingRef.current
                        )
                            return
                        const chunk = microphonePcm(samples)
                        setMicLevel(chunk.level)
                        const pending = startupAudioRef.current
                        if (pending) {
                            pending.samples += samples.length
                            if (pending.samples > 16000 * 5) {
                                stopMicCapture()
                                addSystem(
                                    catalog.voice.startupAudioTimeout,
                                    'error',
                                )
                                return
                            }
                            pending.chunks.push(chunk.data)
                            return
                        }
                        if (!sessionRef.current) return
                        audioStreamOpenRef.current = true
                        sessionRef.current.sendRealtimeInput({
                            audio: {
                                data: chunk.data,
                                mimeType: 'audio/pcm;rate=16000',
                            },
                        })
                    },
                })
                if (controller.signal.aborted) {
                    microphone.stop()
                    return
                }
                microphoneRef.current = microphone
                micCaptureActiveRef.current = true
                setIsMicCaptureActive(true)
                setMicOn(turnOn)
                recordMute('mic_capture_started')
                // Device labels are available now; listing them must not delay capture.
                void refreshDevicesRef.current().catch(() => {})
            } catch (err) {
                if (controller.signal.aborted) return
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
        },
        [
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
            writeMicrophonePreference(deviceId)
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
        playbackRef.current.close()
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

    /** Cancels any scheduled reconnect / goAway rotation. */
    const clearReconnectTimers = useCallback(() => {
        if (reconnectTimerRef.current !== null) {
            clearTimeout(reconnectTimerRef.current)
            reconnectTimerRef.current = null
        }
        if (goAwayTimerRef.current !== null) {
            clearTimeout(goAwayTimerRef.current)
            goAwayTimerRef.current = null
        }
    }, [])

    /**
     * Exponential backoff (2^(n-1) s, cap 30 s), reset on a completed setup —
     * native's `_scheduleReconnect`. Only ever runs while the logical session
     * is active; the explicit End cancels it.
     */
    const scheduleReconnect = useCallback(() => {
        if (!sessionActiveRef.current || reconnectTimerRef.current !== null) {
            return
        }
        reconnectAttemptRef.current += 1
        const seconds = Math.min(30, 2 ** (reconnectAttemptRef.current - 1))
        addSystem(catalog.voice.systemReconnecting({ seconds }), 'info')
        reconnectTimerRef.current = setTimeout(() => {
            reconnectTimerRef.current = null
            if (!sessionActiveRef.current) return
            void connectAttemptRef.current()
        }, seconds * 1000)
    }, [addSystem, catalog])

    /**
     * One connection attempt against a fresh single-use token — the body of
     * both the initial connect and every reconnect. A failure never ends the
     * session: it is reported as a transient notice and retried on backoff,
     * so only the explicit End (or the account unmounting) can close a
     * conversation. `generation` guards every callback against a superseded
     * socket.
     */
    const connectAttempt = useCallback(async () => {
        if (!sessionActiveRef.current) return
        const generation = ++generationRef.current
        connectAbortRef.current?.abort()
        const controller = new AbortController()
        connectAbortRef.current = controller
        applyStatus('connecting')

        try {
            // The snapshot is best-effort: a failed builder must never
            // block the session, it only costs the USER_CONTEXT block.
            const mintArgs = await optsRef.current
                .buildMintArgs?.()
                .catch(() => undefined)
            const minted = await convex.action(
                api.v1.live.actions.requestLiveToken,
                { ...mintArgs, platform: 'web', appVersion: WEB_LIVE_VERSION },
            )
            if (generation !== generationRef.current) return
            if (!sessionActiveRef.current) return
            // A refused mint (rate limit) fails identically on every attempt,
            // so the session ends here instead of looping on the reconnect
            // backoff. The transcript stays: only the explicit End clears it.
            if ('error' in minted) {
                addSystem(catalog.voice.systemUnavailable, 'error')
                recordHistory('error', 'local', {
                    message: `Live token refused: ${minted.error}`,
                    isTransient: false,
                })
                sessionActiveRef.current = false
                stopMicCapture()
                stopPlayback()
                clearReconnectTimers()
                applyStatus('disconnected')
                return
            }
            const { token, model } = minted
            const tokenNotice = catalog.voice.systemTokenReceived({ model })
            addSystem(tokenNotice, 'info')
            // The model is only known now, so this is where the session row
            // becomes uploadable.
            historyRef.current?.open(model)
            modelRef.current = model
            const sessionId = historyRef.current?.sessionId
            if (!sessionStartedMetricSentRef.current && sessionId) {
                sessionStartedMetricSentRef.current = true
                // Reconnects reuse the recorder and must not count another session.
                void recordAgentSessionStarted(convex, {
                    sessionId,
                    model,
                    resumed: false,
                })
            }
            recordHistory('system', 'local', { message: tokenNotice })

            const seenCalls = new Set<string>()
            const cancelledCalls = new Set<string>()
            const toolContext = optsRef.current.context
            const conversation = conversationLogRef.current
            const recorder = historyRef.current
            const current = () =>
                generation === generationRef.current && sessionActiveRef.current
            const session = await connectGeminiLive({
                token,
                model,
                signal: controller.signal,
                callbacks: {
                    onmessage: (msg: LiveServerMessage) => {
                        if (generation !== generationRef.current) return
                        for (const fc of msg.toolCall?.functionCalls ?? []) {
                            if (!fc.id || !fc.name || seenCalls.has(fc.id))
                                continue
                            seenCalls.add(fc.id)
                            const { id, name } = fc
                            const args = (fc.args ?? {}) as Record<
                                string,
                                unknown
                            >
                            addToolCall(id, name, args)
                            conversation.push({
                                type: 'tool_call',
                                id,
                                name,
                                args,
                            })
                            recorder?.record(
                                'tool_call',
                                'server',
                                { id, name, args },
                                'tool',
                            )
                            toolsSettledRef.current = toolsSettledRef.current
                                .then(async () => {
                                    if (!current() || cancelledCalls.has(id))
                                        return
                                    let result: Record<string, unknown>
                                    try {
                                        result = await executeToolCall(
                                            toolContext,
                                            name,
                                            args,
                                        )
                                    } catch {
                                        result = {
                                            error: 'Tool execution failed',
                                        }
                                    }
                                    // A committed write stays in its original conversation even if
                                    // cancellation or a disconnect arrived while it was executing.
                                    conversation.push({
                                        type: 'tool_result',
                                        id,
                                        name,
                                        result,
                                    })
                                    recorder?.record(
                                        'tool_result',
                                        'client',
                                        { id, name, result },
                                        'tool',
                                    )
                                    if (
                                        historyRef.current === recorder &&
                                        !cancelledCalls.has(id)
                                    )
                                        completeToolCall(id, result)
                                    if (!current() || cancelledCalls.has(id))
                                        return
                                    session.sendToolResponse({
                                        functionResponses: [
                                            { id, name, response: { result } },
                                        ],
                                    })
                                })
                                .catch((error) =>
                                    console.warn(
                                        'Live tool response failed',
                                        error,
                                    ),
                                )
                        }

                        if (msg.toolCallCancellation) {
                            const ids = (
                                msg.toolCallCancellation.ids ?? []
                            ).filter((x): x is string => typeof x === 'string')
                            for (const id of ids) cancelledCalls.add(id)
                            cancelToolCalls(ids)
                            conversationLogRef.current.push({
                                type: 'tool_cancelled',
                            })
                            recordHistory(
                                'tool_cancelled',
                                'server',
                                { ids },
                                'tool',
                            )
                        }

                        if (msg.usageMetadata) {
                            // Main derives interaction metrics from these history events.
                            // Only session totals are sent separately when the session ends.
                            sessionCostTrackerRef.current.recordUsage({
                                model,
                                mode:
                                    sessionModeRef.current === 'audio'
                                        ? 'voice'
                                        : 'text',
                                usage: msg.usageMetadata,
                            })
                            recordHistory('usage_metadata', 'server', {
                                ...msg.usageMetadata,
                                model,
                                mode: sessionModeRef.current,
                            })
                        }
                        if (msg.goAway) {
                            recordHistory('go_away', 'server', {
                                timeLeft: msg.goAway.timeLeft,
                            })
                            // Rotate shortly before the announced kill —
                            // native's `_handleGoAway`. The transcript seed
                            // restores context on the new connection.
                            const remaining =
                                parseGoogleDuration(msg.goAway.timeLeft) ?? 5000
                            const delay =
                                remaining > 2000 ? remaining - 2000 : 100
                            if (goAwayTimerRef.current !== null) {
                                clearTimeout(goAwayTimerRef.current)
                            }
                            goAwayTimerRef.current = setTimeout(() => {
                                goAwayTimerRef.current = null
                                if (!sessionActiveRef.current) return
                                if (generation !== generationRef.current) {
                                    return
                                }
                                // Supersede this socket first so its onclose
                                // is ignored, then reconnect immediately.
                                generationRef.current += 1
                                sessionRef.current = null
                                playbackRef.current.interrupt()
                                try {
                                    session.close()
                                } catch {
                                    // Already closing — rotation proceeds.
                                }
                                void connectAttemptRef.current()
                            }, delay)
                        }
                        if (msg.sessionResumptionUpdate) {
                            // Only the two booleans, never the handle —
                            // native redacts it from the wire as well.
                            recordHistory(
                                'session_resumption_update',
                                'server',
                                {
                                    resumable:
                                        msg.sessionResumptionUpdate.resumable ??
                                        false,
                                    hasNewHandle: Boolean(
                                        msg.sessionResumptionUpdate.newHandle,
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
                            conversationLogRef.current.push({
                                type: 'agent_interrupted',
                            })
                            recordHistory('agent_interrupted', 'server', {
                                reason: 'server_interrupted',
                            })
                            discardOutputRef.current = true
                            playbackRef.current.interrupt()
                            finalisePendingAgent({ interrupted: true })
                        }

                        const parts = sc.modelTurn?.parts
                        if (parts) {
                            const playable =
                                audioPlaybackEnabledRef.current &&
                                !discardOutputRef.current
                            for (const part of parts) {
                                if (part.thought) continue
                                if (
                                    playable &&
                                    part.inlineData?.data &&
                                    /^audio\/pcm(?:;|$)/.test(
                                        part.inlineData.mimeType ?? '',
                                    )
                                ) {
                                    try {
                                        playbackRef.current.enqueue(
                                            part.inlineData.data,
                                            part.inlineData.mimeType ?? '',
                                        )
                                    } catch (error) {
                                        recordHistory('error', 'local', {
                                            message: String(error),
                                        })
                                    }
                                }
                                if (part.text && !outputText) {
                                    appendAgent(part.text)
                                }
                            }
                        }

                        if (sc.turnComplete) {
                            conversationLogRef.current.push({
                                type: 'agent_turn_complete',
                            })
                            recordHistory('agent_turn_complete', 'server', {
                                model,
                                mode: sessionModeRef.current,
                            })
                            discardOutputRef.current = false
                            finalisePendingAgent()
                        }
                    },
                    onerror: () => {
                        if (generation !== generationRef.current) return
                        addSystem(catalog.voice.systemSocketError, 'error')
                        recordHistory('error', 'local', {
                            message: catalog.voice.systemSocketError,
                            isTransient: true,
                        })
                        // Closing also handles errors that don't close themselves.
                        sessionRef.current?.close()
                    },
                    onclose: (event: CloseEvent) => {
                        if (generation !== generationRef.current) return
                        generationRef.current += 1
                        sessionRef.current = null
                        audioStreamOpenRef.current = false
                        playbackRef.current.interrupt()
                        if (startupAudioRef.current) stopMicCapture()
                        finalisePendingUser()
                        finalisePendingAgent()
                        // The explicit End already cleaned everything up —
                        // this close is just its acknowledgement.
                        if (!sessionActiveRef.current) return
                        addSystem(catalog.voice.systemDisconnected, 'info')
                        recordHistory('disconnected', 'server', {
                            code: event.code,
                            reason: event.reason,
                        })
                        // Suspended, not ended (native's contract): the
                        // conversation continues on the next socket. The
                        // transcript, the typed queue and the mic capture all
                        // stay — chunks are simply dropped while the session
                        // handle is null.
                        historyRef.current?.markStatus('suspended')
                        applyStatus('connecting')
                        scheduleReconnect()
                    },
                },
            })

            if (
                generation !== generationRef.current ||
                !sessionActiveRef.current
            ) {
                // Superseded (goAway rotation, explicit End) while the
                // handshake was in flight.
                try {
                    session.close()
                } catch {
                    // Already closed.
                }
                return
            }
            await toolsSettledRef.current
            if (!current()) {
                session.close()
                return
            }
            sessionRef.current = session
            reconnectAttemptRef.current = 0
            applyStatus('connected')
            historyRef.current?.markStatus('active')
            recordHistory('connected', 'local')
            addSystem(
                sessionModeRef.current === 'audio'
                    ? catalog.voice.systemConnected
                    : catalog.voice.systemConnectedTyping,
                'success',
            )
            // Every connect is a fresh server session; restore the
            // conversation from the event log before anything else is sent,
            // so queued messages and live audio land after the model regained
            // its context — the same ordering contract as native.
            const seed = buildConversationSeed(conversationLogRef.current, {
                pendingTexts: pendingTextRef.current,
            })
            if (seed) {
                session.sendClientContent({
                    turns: [{ role: 'user', parts: [{ text: seed }] }],
                    turnComplete: false,
                })
                recordHistory('context_seeded', 'local', {
                    chars: seed.length,
                })
            }
            flushPendingText()
            const pendingAudio = startupAudioRef.current
            startupAudioRef.current = null
            if (micOnRef.current && !composingRef.current) {
                for (const data of pendingAudio?.chunks ?? []) {
                    session.sendRealtimeInput({
                        audio: { data, mimeType: 'audio/pcm;rate=16000' },
                    })
                    audioStreamOpenRef.current = true
                }
            }
        } catch (err) {
            if (generation !== generationRef.current) return
            if (startupAudioRef.current) stopMicCapture()
            playbackRef.current.interrupt()
            const message = catalog.voice.systemConnectionFailed({
                error: err instanceof Error ? err.message : String(err),
            })
            addSystem(message, 'error')
            recordHistory('error', 'local', {
                message,
                isTransient: true,
            })
            // Keep the transcript and the typed queue; retry on backoff.
            // Only the explicit End closes the conversation.
            if (sessionActiveRef.current) {
                scheduleReconnect()
            } else {
                applyStatus('disconnected')
            }
        }
    }, [
        convex,
        catalog,
        applyStatus,
        clearReconnectTimers,
        stopPlayback,
        stopMicCapture,
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
        scheduleReconnect,
    ])

    // `scheduleReconnect` fires through this ref — the two reference each
    // other, so the cycle is broken with a ref assignment.
    useEffect(() => {
        connectAttemptRef.current = connectAttempt
    }, [connectAttempt])

    /**
     * Starts the logical session — the user-facing connect. Reconnects after
     * drops are internal (`connectAttempt` + `scheduleReconnect`); calling
     * this while a session is active does nothing.
     */
    const connect = useCallback(
        async (mode: SessionMode = 'audio') => {
            if (sessionActiveRef.current) return
            if (statusRef.current !== 'disconnected') return
            sessionActiveRef.current = true
            sessionModeRef.current = mode
            reconnectAttemptRef.current = 0
            conversationLogRef.current = []
            modelRef.current = null
            sessionStartedMetricSentRef.current = false
            sessionCostMetricSentRef.current = false
            sessionCostTrackerRef.current = new AgentSessionCostTracker()
            pendingUserIdRef.current = null
            pendingAgentIdRef.current = null
            audioStreamOpenRef.current = false
            discardOutputRef.current = false
            audioPlaybackEnabledRef.current =
                mode === 'audio' ? true : RESPOND_TO_TEXT_WITH_AUDIO
            addSystem(catalog.voice.systemConnecting, 'info')

            // One recorder per logical session — reconnects reuse it, so one
            // conversation stays one `voiceSessions` row. Created before the
            // first await so a turn typed while connecting still lands in the
            // same history.
            historyRef.current = createVoiceHistoryRecorder(
                convex,
                () => ownerIdRef.current,
            )
            recordHistory('connecting', 'local', {
                message: catalog.voice.systemConnecting,
            })

            if (mode === 'audio') {
                startupAudioRef.current = { chunks: [], samples: 0 }
                await Promise.all([connectAttempt(), openMic({ turnOn: true })])
            } else {
                await connectAttempt()
            }
        },
        [convex, catalog, addSystem, recordHistory, connectAttempt, openMic],
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
            if (status !== 'connected' && pendingTextRef.current.length >= 20) {
                addSystem(catalog.voice.systemUnavailable, 'error')
                return
            }

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
        [
            appendTypedUser,
            endAudioStream,
            connect,
            recordSendMessage,
            addSystem,
            catalog,
        ],
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
            if (started && startupAudioRef.current) stopMicCapture()
            if (composing) setMicLevel(0)
            if (
                started &&
                statusRef.current === 'connected' &&
                micCaptureActiveRef.current
            ) {
                endAudioStream()
            }
        },
        [endAudioStream, recordMute, stopMicCapture],
    )

    // Disconnect — the explicit End. The only path that closes a
    // conversation for good (a dropped socket suspends and reconnects), and
    // the only one that clears the transcript, like native's factory dropping
    // the command.
    const disconnect = useCallback(() => {
        recordHistory('end_session', 'client')
        const sessionId = historyRef.current?.sessionId
        if (sessionId && !sessionCostMetricSentRef.current) {
            sessionCostMetricSentRef.current = true
            for (const sample of sessionCostTrackerRef.current.samples()) {
                void recordAgentSessionCost(convex, { sessionId, ...sample })
            }
        }
        sessionActiveRef.current = false
        clearReconnectTimers()
        // Invalidate the socket's callbacks and any in-flight attempt before
        // closing, so the close below is not mistaken for a drop.
        generationRef.current += 1
        connectAbortRef.current?.abort()
        endAudioStream()
        stopMicCapture()
        stopPlayback()
        sessionRef.current?.close()
        sessionRef.current = null
        audioStreamOpenRef.current = false
        pendingTextRef.current = []
        conversationLogRef.current = []
        discardOutputRef.current = false
        audioPlaybackEnabledRef.current = true
        applyStatus('disconnected')
        finalisePendingUser()
        finalisePendingAgent()
        setMessages([])
        // Ends the row and flushes the tail, native's `endExplicitly` + flush.
        const recorder = historyRef.current
        void toolsSettledRef.current.then(() =>
            recorder?.end({ explicit: true }),
        )
    }, [
        convex,
        endAudioStream,
        stopMicCapture,
        stopPlayback,
        applyStatus,
        finalisePendingUser,
        finalisePendingAgent,
        recordHistory,
        clearReconnectTimers,
    ])

    /**
     * The assistant screen is on screen again. Mirrors
     * `_VoiceScreenState.initState` re-attaching to the factory's active
     * command in `apps/native/lib/screens/voice.dart`: there is nothing to
     * rebuild, because the session and its transcript never went away.
     */
    const attach = useCallback(() => {
        if (statusRef.current === 'disconnected') return
        recordHistory('screen_attached', 'client')
    }, [recordHistory])

    /**
     * The assistant screen went away but the account did not — the user simply
     * navigated elsewhere. Mirrors `_VoiceScreenState.dispose`: the current
     * answer is interrupted, the audio turn is flushed and the mic is released,
     * while the socket, the running agent and the transcript stay. Coming back
     * to `/add` finds the conversation where it was left.
     *
     * The mic release is not optional on web the way it reads on native: a
     * browser keeps its recording indicator lit for as long as the track is
     * live, and the user is no longer looking at the screen that explains it.
     */
    const detach = useCallback(() => {
        if (statusRef.current === 'disconnected') {
            // The conversation is over (only the explicit End gets here, and
            // it already cleared the transcript). Nothing to detach from.
            return
        }
        recordHistory('screen_detached', 'client', {
            micMuted: true,
            sessionKeptActive: true,
        })
        // Native's `interruptAgentResponse('screen_detached')`: stop speaking
        // and drop what the server has already queued for this turn. Both flags
        // are cleared again by the next spoken turn / `turnComplete`.
        audioPlaybackEnabledRef.current = false
        discardOutputRef.current = true
        playbackRef.current.interrupt()
        finalisePendingAgent({ interrupted: true })
        endAudioStream()
        stopMicCapture()
        stopPlayback()
    }, [
        recordHistory,
        finalisePendingAgent,
        endAudioStream,
        stopMicCapture,
        stopPlayback,
    ])

    useEffect(() => {
        const hidden = () => {
            if (document.visibilityState === 'hidden') detach()
        }
        document.addEventListener('visibilitychange', hidden)
        return () => document.removeEventListener('visibilitychange', hidden)
    }, [detach])

    const clearMessages = useCallback(() => setMessages([]), [])

    /**
     * Flag an agent bubble as reported, so it can say so after the toast is
     * gone. Purely cosmetic — the report itself is already on the server.
     */
    const markReported = useCallback((id: string) => {
        setMessages((prev) =>
            prev.map((m) =>
                m.id === id && m.kind === 'agent'
                    ? { ...m, reported: true }
                    : m,
            ),
        )
    }, [])

    /**
     * Where the conversation lives on the backend, for a report to point at.
     * Read at report time rather than published as state: both values are set
     * once per session and re-rendering the chat when they arrive buys nothing.
     */
    const getSessionInfo = useCallback(
        () => ({
            sessionId: historyRef.current?.sessionId,
            model: modelRef.current ?? undefined,
        }),
        [],
    )

    /*
     * Ends the session when the *account* goes away, which is the only thing
     * that unmounts `VoiceProvider` — it sits inside `AuthProvider`, above the
     * router. This used to hang off the `/add` page, where it fired on every
     * navigation: it killed the socket mid-answer and wrote a `voiceSessions`
     * row marked `endedExplicitly` for what was only a tab change.
     */
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
        attach,
        detach,
        openMic,
        setMicOn,
        sendText,
        setComposing,
        messages,
        clearMessages,
        markReported,
        getSessionInfo,
    }
}

/**
 * The session object `VoiceProvider` publishes and `useVoiceSession` reads.
 */
export type VoiceSession = ReturnType<typeof useVoice>
