import { api } from '@wallet-bot/backend/api'
import {
    Button,
    CircularProgress,
    IconButton,
    MenuButton,
    MenuItem,
} from 'actify'
import { useQuery } from 'convex/react'
import {
    type KeyboardEvent,
    type PointerEvent,
    useCallback,
    useEffect,
    useRef,
    useState,
} from 'react'
import { useNavigate } from 'react-router-dom'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
import type { ChatMessage } from '@/hooks/use-voice'
import { useVoiceSession } from '@/hooks/use-voice-session'
import { useFormatLocale, useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'
import {
    ReportResponseSheet,
    type ReportTarget,
} from '@/pages/add/report-response-sheet'
import { ActionWidget } from '@/pages/add-action-widget'

// Constants

/** Flutter's long-press timeout — the composer's push-to-talk threshold. */
const LONG_PRESS_MS = 500

/** Four lines of the composer at `text-sm`, plus its vertical padding. */
const COMPOSER_MAX_HEIGHT = 104

// Helpers

function formatTime(date: Date, locale: string) {
    return date.toLocaleTimeString(locale, {
        hour12: false,
        hour: '2-digit',
        minute: '2-digit',
    })
}

function formatJson(data: Record<string, unknown>): string {
    if (Object.keys(data).length === 0) return '{}'
    return Object.entries(data)
        .map(
            ([k, v]) =>
                `${k}: ${typeof v === 'string' ? v : JSON.stringify(v)}`,
        )
        .join('\n')
}

// Speaking dots indicator

function SpeakingDots({ className }: { className?: string }) {
    const t = useT()
    return (
        <span
            role="status"
            aria-label={t.voice.speaking}
            className={cn('inline-flex items-end gap-1', className)}
        >
            <span className="size-1.5 animate-bounce rounded-full bg-current" />
            <span className="size-1.5 animate-bounce rounded-full bg-current [animation-delay:120ms]" />
            <span className="size-1.5 animate-bounce rounded-full bg-current [animation-delay:240ms]" />
        </span>
    )
}

// Microphone picker

/**
 * The input-device picker: an M3 menu button in the app bar carrying the live
 * microphone's name, opening the Material menu of the other inputs. Web-only —
 * native always records from the platform's default input
 * (`voice/mic_capture.dart`), so there is nothing to mirror; the app bar keeps
 * the choice one tap away without spending a row of the control bar on it.
 *
 * `MenuButton` is actify's `MenuTrigger` + `MenuPopover` + `Menu`, so the popup
 * is a real Material menu — `--md-sys-color-surface-container`, M3 state-layer
 * opacities, ripple and focus ring included. The selected input is marked the
 * way the rest of the app marks a chosen option (`OptionSheet`) and the way
 * native does (`Icons.check_circle_rounded`).
 *
 * Selection is handled per item: `MenuButton` spreads its own props onto the
 * `MenuTrigger`, not onto the `Menu` it renders, so `selectionMode`,
 * `selectedKeys` and a menu-level `onAction` are silently dropped (verified in
 * a browser — the items stayed `role="menuitem"` and picking one did nothing).
 * `MenuItem.onAction` reaches react-aria directly, which is also the pattern
 * actify's own docs use for a selectable menu.
 */
function MicPicker({
    devices,
    selectedDeviceId,
    onSelect,
}: {
    devices: MediaDeviceInfo[]
    selectedDeviceId: string
    onSelect: (deviceId: string) => void
}) {
    const t = useT()
    // Labels are empty until the user grants permission; the id is all we have.
    const deviceLabel = (device: MediaDeviceInfo) =>
        device.label || device.deviceId
    const selected = devices.find(
        (device) => device.deviceId === selectedDeviceId,
    )

    return (
        <MenuButton
            label={
                <Button
                    variant="outlined"
                    aria-label={t.voice.microphone}
                    // Share the bar with the title instead of truncating it:
                    // a proportional cap on phones, a fixed one from `sm` up.
                    className="max-w-[40vw] sm:max-w-56"
                >
                    <span className="flex min-w-0 items-center gap-1.5">
                        <Icon name="mic" size={18} />
                        <span className="min-w-0 truncate">
                            {selected
                                ? deviceLabel(selected)
                                : t.voice.microphone}
                        </span>
                        <Icon name="arrow_drop_down" size={18} />
                    </span>
                </Button>
            }
            popoverProps={{ placement: 'bottom end' }}
        >
            {devices.map((device) => (
                <MenuItem
                    key={device.deviceId}
                    id={device.deviceId}
                    textValue={deviceLabel(device)}
                    onAction={() => onSelect(device.deviceId)}
                >
                    <span className="flex w-full min-w-0 items-center gap-4">
                        <span className="m3-body-large min-w-0 flex-1 truncate">
                            {deviceLabel(device)}
                        </span>
                        {device.deviceId === selectedDeviceId ? (
                            <Icon
                                name="check_circle"
                                filled
                                className="shrink-0 text-primary"
                            />
                        ) : null}
                    </span>
                </MenuItem>
            ))}
        </MenuButton>
    )
}

// Message renderers

function UserBubble({
    message,
}: {
    message: Extract<ChatMessage, { kind: 'user' }>
}) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const text = message.text.trim()
    return (
        <div className="flex justify-end">
            <div className="flex max-w-[78%] flex-col items-end gap-1">
                <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <span>{formatTime(message.at, formatLocale)}</span>
                    <span className="font-medium">{t.voice.you}</span>
                </div>
                <div className="rounded-2xl rounded-br-sm bg-primary-container px-4 py-2.5 text-on-primary-container">
                    {text && (
                        <p className="whitespace-pre-wrap text-sm leading-snug">
                            {text}
                        </p>
                    )}
                    {!message.isFinal && (
                        <div
                            className={cn(
                                'text-on-primary-container/70',
                                text && 'mt-1.5',
                            )}
                        >
                            <SpeakingDots />
                        </div>
                    )}
                </div>
            </div>
        </div>
    )
}

function AgentBubble({
    message,
    onReport,
    showReportButton,
}: {
    message: Extract<ChatMessage, { kind: 'agent' }>
    onReport: (message: Extract<ChatMessage, { kind: 'agent' }>) => void
    showReportButton: boolean
}) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const text = message.text.trim()
    return (
        <div className="flex justify-start">
            <div className="flex max-w-[82%] items-start gap-2">
                <div className="flex flex-col items-start gap-1">
                    <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                        <span className="font-medium">{t.voice.agent}</span>
                        <span>{formatTime(message.at, formatLocale)}</span>
                        {/*
                         * Always rendered, only dimmed. Google Play requires a
                         * way to flag generated content without leaving the app,
                         * and a control that appears on hover is not there at
                         * all on a touch screen or to a keyboard user scanning
                         * the page.
                         */}
                        {showReportButton && text && !message.reported && (
                            <button
                                type="button"
                                aria-label={t.agentReport.action}
                                title={t.agentReport.action}
                                onClick={() => onReport(message)}
                                className="rounded-full p-0.5 opacity-60 transition-opacity hover:opacity-100 focus-visible:opacity-100"
                            >
                                <Icon name="flag" size={14} />
                            </button>
                        )}
                        {message.reported && (
                            <span className="flex items-center gap-1">
                                <Icon name="flag" filled size={14} />
                                {t.agentReport.badge}
                            </span>
                        )}
                    </div>
                    <div className="rounded-2xl rounded-tl-sm bg-surface-container-highest px-4 py-2.5 text-on-surface">
                        {text && (
                            <p className="whitespace-pre-wrap text-sm leading-snug">
                                {text}
                            </p>
                        )}
                        {!message.isFinal && (
                            <div
                                className={cn(
                                    'text-muted-foreground',
                                    text && 'mt-1.5',
                                )}
                            >
                                <SpeakingDots />
                            </div>
                        )}
                        {message.wasInterrupted && (
                            <p className="mt-1.5 text-xs italic text-muted-foreground">
                                {t.voice.interrupted}
                            </p>
                        )}
                    </div>
                </div>
            </div>
        </div>
    )
}

function ToolCard({
    message,
    debugEnabled,
}: {
    message: Extract<ChatMessage, { kind: 'tool' }>
    debugEnabled: boolean
}) {
    const t = useT()
    const status = message.status
    const statusIcon =
        status === 'pending'
            ? 'hourglass_top'
            : status === 'completed'
              ? 'check_circle'
              : 'cancel'
    const statusColor =
        status === 'pending'
            ? 'text-amber-600 dark:text-amber-400'
            : status === 'completed'
              ? 'text-green-600 dark:text-green-400'
              : 'text-destructive'
    const statusLabel =
        status === 'pending'
            ? t.voice.toolRunning
            : status === 'completed'
              ? t.voice.toolDone
              : t.voice.toolCancelled

    return (
        <div className="flex justify-center">
            <div className="w-full max-w-[92%] rounded-lg border bg-card p-3 text-sm">
                <div className="flex items-center gap-2">
                    <Icon
                        name="build"
                        filled
                        size={14}
                        className="text-on-surface-variant"
                    />
                    <span className="text-xs uppercase tracking-wider text-muted-foreground">
                        {t.voice.tool}
                    </span>
                    <span className="flex-1 truncate font-mono text-sm font-semibold">
                        {message.name}
                    </span>
                    <span
                        className={cn(
                            'flex items-center gap-1 text-xs',
                            statusColor,
                        )}
                    >
                        <Icon name={statusIcon} filled size={14} />
                        {statusLabel}
                    </span>
                </div>
                {debugEnabled && Object.keys(message.args).length > 0 && (
                    <KvBlock label="args" data={message.args} />
                )}
                {debugEnabled && message.result && (
                    <KvBlock label="result" data={message.result} />
                )}
            </div>
        </div>
    )
}

function KvBlock({
    label,
    data,
}: {
    label: string
    data: Record<string, unknown>
}) {
    return (
        <div className="mt-2 rounded-md bg-muted/60 p-2">
            <div className="mb-1 text-[10px] uppercase tracking-wider text-muted-foreground">
                {label}
            </div>
            <pre className="whitespace-pre-wrap wrap-break-word font-mono text-[11px] leading-tight">
                {formatJson(data)}
            </pre>
        </div>
    )
}

function SystemLine({
    message,
}: {
    message: Extract<ChatMessage, { kind: 'system' }>
}) {
    const icon =
        message.level === 'error'
            ? 'error'
            : message.level === 'success'
              ? 'check_circle'
              : 'info'
    const color =
        message.level === 'error'
            ? 'text-destructive'
            : message.level === 'success'
              ? 'text-primary'
              : 'text-muted-foreground'
    return (
        <div className="flex justify-center">
            <div className={cn('flex items-center gap-1.5 text-xs', color)}>
                <Icon name={icon} filled size={14} />
                <span>{message.message}</span>
            </div>
        </div>
    )
}

function MessageView({
    message,
    debugEnabled,
    onReport,
    showReportButton,
}: {
    message: ChatMessage
    debugEnabled: boolean
    onReport: (message: Extract<ChatMessage, { kind: 'agent' }>) => void
    showReportButton: boolean
}) {
    switch (message.kind) {
        case 'user':
            return <UserBubble message={message} />
        case 'agent':
            return (
                <AgentBubble
                    message={message}
                    onReport={onReport}
                    showReportButton={showReportButton}
                />
            )
        case 'tool':
            return <ToolCard message={message} debugEnabled={debugEnabled} />
        case 'system':
            return <SystemLine message={message} />
        case 'action-result':
            return <ActionWidget message={message} />
    }
}

// Status pill

function StatusPill({
    status,
}: {
    status: 'idle' | 'connecting' | 'connected'
}) {
    const t = useT()
    const color =
        status === 'connected'
            ? 'border-primary text-primary'
            : status === 'connecting'
              ? 'border-tertiary text-tertiary'
              : 'border-outline text-on-surface-variant'
    const label =
        status === 'connected'
            ? t.voice.statusConnected
            : status === 'connecting'
              ? t.voice.statusConnecting
              : t.voice.statusIdle
    return (
        <div
            className={cn(
                'inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs',
                color,
            )}
        >
            <span
                className={cn(
                    'size-2 rounded-full bg-current',
                    status === 'connected' && 'animate-pulse',
                )}
            />
            {label}
        </div>
    )
}

// Empty state

function EmptyState({ isConnecting }: { isConnecting: boolean }) {
    const t = useT()
    return (
        <div className="flex flex-1 flex-col items-center justify-center gap-3 text-muted-foreground">
            {/* `cloud_sync_rounded` / `mic_none_rounded`, as in `_EmptyState`. */}
            <Icon
                name={isConnecting ? 'cloud_sync' : 'mic'}
                filled={isConnecting}
                size={48}
                className="opacity-50"
            />
            <p className="text-sm">
                {isConnecting ? t.voice.connectingEllipsis : t.voice.tapToStart}
            </p>
        </div>
    )
}

// Composer

/**
 * The text field of the control bar, porting `_TextComposer`: a single line
 * that grows to four before it scrolls. Enter sends, Shift+Enter breaks.
 */
function Composer({
    value,
    onChange,
    onSend,
}: {
    value: string
    onChange: (value: string) => void
    onSend: () => void
}) {
    const t = useT()
    const ref = useRef<HTMLTextAreaElement>(null)

    useEffect(() => {
        const el = ref.current
        if (!el) return
        // Collapse first, then measure the content — an empty composer is one
        // row, anything else grows up to the cap and scrolls past it.
        el.style.height = 'auto'
        if (value === '') return
        el.style.height = `${Math.min(el.scrollHeight, COMPOSER_MAX_HEIGHT)}px`
    }, [value])

    const handleKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
        if (event.key !== 'Enter' || event.shiftKey) return
        event.preventDefault()
        onSend()
    }

    return (
        <div className="min-w-0 flex-1 rounded-3xl border border-outline-variant bg-surface px-4">
            <textarea
                ref={ref}
                rows={1}
                value={value}
                onChange={(event) => onChange(event.target.value)}
                onKeyDown={handleKeyDown}
                placeholder={t.voice.typeMessage}
                aria-label={t.voice.typeMessage}
                className="block w-full resize-none bg-transparent py-3 text-sm leading-snug text-on-surface outline-none placeholder:text-muted-foreground"
            />
        </div>
    )
}

// Primary action button

/**
 * The single trailing button of the control bar, porting
 * `_PrimaryActionButton`: a send arrow while the composer holds text,
 * otherwise the mic — tap to toggle, press and hold to talk.
 */
function PrimaryActionButton({
    isConnecting,
    isMicCaptureActive,
    isMicMuted,
    hasText,
    micLabel,
    onTap,
    onLongPressStart,
    onLongPressEnd,
    onSend,
}: {
    isConnecting: boolean
    isMicCaptureActive: boolean
    isMicMuted: boolean
    hasText: boolean
    micLabel: string
    onTap: () => void
    onLongPressStart: () => void
    onLongPressEnd: () => void
    onSend: () => void
}) {
    const t = useT()
    const timerRef = useRef<number | null>(null)
    const isLongPressRef = useRef(false)

    const clearTimer = useCallback(() => {
        if (timerRef.current === null) return
        window.clearTimeout(timerRef.current)
        timerRef.current = null
    }, [])

    useEffect(() => clearTimer, [clearTimer])

    const showMutedStyle = !hasText && isMicCaptureActive && isMicMuted
    const base =
        'grid size-14 shrink-0 place-items-center rounded-full transition-colors'
    const className = showMutedStyle
        ? cn(base, 'border-[1.5px] border-outline text-on-surface-variant')
        : cn(
              base,
              'bg-primary-container text-on-primary-container shadow-level-2',
          )

    if (hasText) {
        return (
            <button
                type="button"
                onClick={onSend}
                aria-label={t.voice.send}
                className={className}
            >
                <Icon name="arrow_upward" filled size={26} />
            </button>
        )
    }

    const handlePointerDown = (event: PointerEvent<HTMLButtonElement>) => {
        if (event.button !== 0) return
        isLongPressRef.current = false
        timerRef.current = window.setTimeout(() => {
            timerRef.current = null
            isLongPressRef.current = true
            onLongPressStart()
        }, LONG_PRESS_MS)
    }

    const handlePointerUp = () => {
        clearTimer()
        if (!isLongPressRef.current) {
            onTap()
            return
        }
        isLongPressRef.current = false
        onLongPressEnd()
    }

    const handlePointerAbort = () => {
        clearTimer()
        if (!isLongPressRef.current) return
        isLongPressRef.current = false
        onLongPressEnd()
    }

    const handleKeyDown = (event: KeyboardEvent<HTMLButtonElement>) => {
        if (event.key !== 'Enter' && event.key !== ' ') return
        event.preventDefault()
        onTap()
    }

    return (
        <button
            type="button"
            aria-label={micLabel}
            className={cn(className, 'touch-none select-none')}
            onPointerDown={handlePointerDown}
            onPointerUp={handlePointerUp}
            onPointerCancel={handlePointerAbort}
            onPointerLeave={handlePointerAbort}
            onKeyDown={handleKeyDown}
            onContextMenu={(event) => event.preventDefault()}
        >
            {isConnecting ? (
                <CircularProgress isIndeterminate size="xs" />
            ) : (
                <Icon
                    name={showMutedStyle ? 'mic_off' : 'mic'}
                    filled
                    size={26}
                />
            )}
        </button>
    )
}

// Page

export function Add() {
    const t = useT()
    const navigate = useNavigate()
    // The session belongs to `VoiceProvider`, above the router: this page shows
    // it, it does not own it. Leaving the page no longer ends the conversation.
    const voice = useVoiceSession()
    const flags = useQuery(api.v1.featureFlags.queries.getMyFlags)
    const debugEnabled = flags?.debugToolCalls ?? false
    /*
     * Defaults to shown while the query is in flight. This is the control
     * Google Play expects to find on a generated response, so a loading round
     * trip must not be a window where the chat has no visible way to report.
     */
    const showReportButton = flags?.agentReportButton ?? true
    const [reportTarget, setReportTarget] = useState<ReportTarget | null>(null)
    const [reportSession, setReportSession] = useState<{
        sessionId?: string
        model?: string
    }>({})

    const [text, setText] = useState('')
    const isComposing = text.trim().length > 0

    // Native's `screen_attached` / `screen_detached`, with the same effects:
    // leaving mutes the mic and interrupts the answer in flight, and keeps
    // everything else running. The composer draft stays page-local, as
    // `_textController` does on native.
    const { attach, detach } = voice
    useEffect(() => {
        attach()
        return detach
    }, [attach, detach])

    const status: 'idle' | 'connecting' | 'connected' = voice.isConnected
        ? 'connected'
        : voice.isConnecting
          ? 'connecting'
          : 'idle'

    // Mirrors `_isMicEffectivelyMuted`: nothing reaches the model unless
    // capture is running, the user has the mic on, and they are not typing.
    const isMicMuted =
        !voice.isMicCaptureActive || !voice.isMicOn || isComposing
    const showLevel = voice.isMicCaptureActive && !isMicMuted

    const bottomRef = useRef<HTMLDivElement>(null)
    useEffect(() => {
        if (voice.messages.length === 0) return
        bottomRef.current?.scrollIntoView({
            behavior: 'smooth',
            block: 'end',
        })
    }, [voice.messages])

    const handleTextChange = (next: string) => {
        setText(next)
        voice.setComposing(next.trim().length > 0)
    }

    const handleSend = () => {
        if (!isComposing) return
        voice.sendText(text)
        setText('')
        voice.setComposing(false)
    }

    /**
     * Starts a session. No transcript wipe here: only the explicit End clears
     * the conversation (a dropped socket reconnects and keeps it), and End
     * already left the log empty.
     */
    const startVoiceSession = () => {
        void voice.connect('audio')
    }

    /**
     * Open the report sheet for one agent turn. The user turn immediately
     * before it travels along: a reply reads very differently next to what
     * prompted it, and a moderator has no other way to see that for a report
     * filed from a local-only account.
     */
    const reportResponse = (
        message: Extract<ChatMessage, { kind: 'agent' }>,
    ) => {
        const index = voice.messages.findIndex((m) => m.id === message.id)
        const preceding = voice.messages
            .slice(0, index === -1 ? undefined : index)
            .findLast((m) => m.kind === 'user')
        setReportSession(voice.getSessionInfo())
        setReportTarget({
            scope: 'response',
            messageId: message.id,
            reportedText: message.text.trim(),
            precedingUserText:
                preceding?.kind === 'user'
                    ? preceding.text.trim() || undefined
                    : undefined,
            occurredAt: message.at,
        })
    }

    /**
     * The fallback entry point, for a reply that was voice-only or has already
     * scrolled out of reach: report the session and let a moderator read it
     * from the replicated history.
     */
    const reportSessionScope = () => {
        setReportSession(voice.getSessionInfo())
        setReportTarget({ scope: 'session' })
    }

    const handleTap = () => {
        if (voice.isConnecting || isComposing) return
        if (!voice.isConnected) {
            startVoiceSession()
            return
        }
        if (!voice.isMicCaptureActive) {
            void voice.openMic({ turnOn: true })
            return
        }
        voice.setMicOn(!voice.isMicOn)
    }

    const handleLongPressStart = () => {
        if (voice.isConnecting || isComposing) return
        if (!voice.isConnected) {
            startVoiceSession()
            return
        }
        if (!voice.isMicCaptureActive) {
            void voice.openMic({ turnOn: true })
            return
        }
        voice.setMicOn(true)
    }

    const handleLongPressEnd = () => {
        if (!voice.isConnected || !voice.isMicCaptureActive) return
        voice.setMicOn(false)
    }

    const micLabel = !voice.isConnected
        ? t.voice.startConversation
        : isMicMuted
          ? t.voice.unmute
          : t.voice.mute

    return (
        <>
            <AppBar
                title={t.voice.title}
                leading={
                    <IconButton
                        aria-label={t.common.goBack}
                        onPress={() => navigate(-1)}
                        className="text-on-surface-variant"
                    >
                        <Icon name="arrow_back" />
                    </IconButton>
                }
                actions={
                    <>
                        {voice.isMicCaptureActive &&
                            voice.devices.length > 1 && (
                                <MicPicker
                                    devices={voice.devices}
                                    selectedDeviceId={voice.selectedDeviceId}
                                    onSelect={(deviceId) =>
                                        void voice.handleDeviceChange(deviceId)
                                    }
                                />
                            )}
                        {voice.isConnected ? (
                            <IconButton
                                aria-label={t.voice.endSession}
                                onPress={voice.disconnect}
                                className="text-error"
                            >
                                <Icon name="call_end" filled />
                            </IconButton>
                        ) : (
                            <div className="pr-2">
                                <StatusPill status={status} />
                            </div>
                        )}
                        <MenuButton
                            label={
                                <IconButton
                                    aria-label={t.agentReport.moreOptions}
                                    className="text-on-surface-variant"
                                >
                                    <Icon name="more_vert" />
                                </IconButton>
                            }
                            popoverProps={{ placement: 'bottom end' }}
                        >
                            <MenuItem
                                id="report-session"
                                textValue={t.agentReport.menuItem}
                                onAction={reportSessionScope}
                            >
                                {t.agentReport.menuItem}
                            </MenuItem>
                        </MenuButton>
                    </>
                }
            />

            <ReportResponseSheet
                open={reportTarget !== null}
                onOpenChange={(next) => {
                    if (!next) setReportTarget(null)
                }}
                target={reportTarget}
                sessionId={reportSession.sessionId}
                model={reportSession.model}
                onReported={voice.markReported}
            />

            <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 py-6">
                {voice.messages.length === 0 ? (
                    <EmptyState isConnecting={voice.isConnecting} />
                ) : (
                    voice.messages.map((m) => (
                        <MessageView
                            key={m.id}
                            message={m}
                            debugEnabled={debugEnabled}
                            onReport={reportResponse}
                            showReportButton={showReportButton}
                        />
                    ))
                )}
                <div ref={bottomRef} aria-hidden className="h-0" />
            </div>

            {/* Control bar — composer plus one primary action, as on native */}
            <div className="shrink-0 bg-surface-container px-3 pt-2 pb-3">
                <div className="mx-auto flex max-w-2xl flex-col gap-2.5">
                    {showLevel && (
                        <div className="h-1 overflow-hidden rounded-full bg-surface-container-highest">
                            <div
                                className="h-full bg-primary transition-all duration-75"
                                style={{
                                    width: `${Math.round(voice.micLevel * 100)}%`,
                                }}
                            />
                        </div>
                    )}

                    <div className="flex items-end gap-2">
                        <Composer
                            value={text}
                            onChange={handleTextChange}
                            onSend={handleSend}
                        />
                        <PrimaryActionButton
                            isConnecting={voice.isConnecting}
                            isMicCaptureActive={voice.isMicCaptureActive}
                            isMicMuted={isMicMuted}
                            hasText={isComposing}
                            micLabel={micLabel}
                            onTap={handleTap}
                            onLongPressStart={handleLongPressStart}
                            onLongPressEnd={handleLongPressEnd}
                            onSend={handleSend}
                        />
                    </div>
                </div>
            </div>
        </>
    )
}
