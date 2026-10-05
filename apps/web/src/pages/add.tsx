import { api } from '@wallet-bot/backend/api'
import { type PromptSuggestion, promptSuggestionKey } from '@wallet-bot/shared'
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
    type RefObject,
    useCallback,
    useEffect,
    useRef,
    useState,
} from 'react'
import { useNavigate } from 'react-router-dom'
import appIcon from '@/assets/favicon.png'
import { AgentGlyph } from '@/components/m3/agent-glyph'
import { AppBar } from '@/components/m3/app-bar'
import { AssistChip } from '@/components/m3/chip'
import { Icon } from '@/components/m3/icon'
import { useEnterSends } from '@/hooks/use-enter-sends'
import { usePromptSuggestions } from '@/hooks/use-prompt-suggestions'
import type { ChatMessage } from '@/hooks/use-voice'
import { useVoiceSession } from '@/hooks/use-voice-session'
import { type Messages, useFormatLocale, useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'
import {
    ReportResponseSheet,
    type ReportTarget,
} from '@/pages/add/report-response-sheet'
import { ActionWidget } from '@/pages/add-action-widget'

// Constants

/** How long the mic has to be held before it is push-to-talk, not a tap. */
const HOLD_MS = 300

/** How far up a hold has to travel to lock the mic open. */
const LOCK_DISTANCE = 80

const WAVEFORM_BARS = 64

/**
 * Whether the chat shows a card ("Herramienta") for each tool call the agent
 * makes. Hidden for now unless `debugToolCalls` is on, as on native
 * (`_kShowToolCards`).
 */
const SHOW_TOOL_CARDS = false

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

function suggestionText(
    t: Messages,
    locale: string,
    s: PromptSuggestion,
): string {
    const m = t.voice.suggestions
    const amount = new Intl.NumberFormat(locale, {
        maximumFractionDigits: 2,
    }).format((s.amountCents ?? 0) / 100)
    const category = s.category ?? ''
    const account = s.account ?? ''
    switch (s.kind) {
        case 'logExpense':
            return s.account === undefined
                ? m.logExpense({ amount, category })
                : m.logExpenseWithAccount({ amount, category, account })
        case 'spentInCategoryThisMonth':
            return m.spentInCategoryThisMonth({ category })
        case 'accountBalance':
            return m.accountBalance({ account })
        case 'topSpendingThisMonth':
            return m.topSpendingThisMonth
        case 'compareCategoryLastMonth':
            return m.compareCategoryLastMonth({ category })
        case 'transfer':
            return m.transfer({
                amount,
                account,
                toAccount: s.toAccount ?? '',
            })
        case 'logIncome':
            return m.logIncome({ amount, account })
        case 'spentWithTag':
            return m.spentWithTag({ tag: s.tag ?? '' })
        case 'recentExpenses':
            return m.recentExpenses
        case 'whatCanYouDo':
            return m.whatCanYouDo
        case 'createCashAccount':
            return m.createCashAccount
        case 'setupCategories':
            return m.setupCategories
        case 'howToLogExpense':
            return m.howToLogExpense
        case 'homeWidget':
            return s.category === undefined
                ? m.homeWidget
                : m.homeWidgetForCategory({ category })
    }
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
                        {message.reported && (
                            <span className="flex items-center gap-1">
                                <Icon name="flag" filled size={14} />
                                {t.agentReport.badge}
                            </span>
                        )}
                    </div>
                    <div className="flex items-center gap-1">
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
                        {/*
                         * Always rendered, only dimmed. Google Play requires a
                         * way to flag generated content without leaving the app,
                         * and a control that appears on hover is not there at
                         * all on a touch screen or to a keyboard user scanning
                         * the page. Centred on the bubble, outside it, so the
                         * hit area never competes with selecting the text.
                         *
                         * It holds its space from the first token but stays
                         * `invisible` until the turn ends, so the bubble never
                         * reflows and there is no control to hit while there is
                         * still nothing finished to report. `visibility:hidden`
                         * also keeps it out of the tab order and off the
                         * accessibility tree, which `opacity-0` would not.
                         * `fill-mode-backwards` holds it transparent through
                         * the delay instead of flashing it first.
                         */}
                        {showReportButton && text && !message.reported && (
                            <button
                                type="button"
                                aria-label={t.agentReport.action}
                                title={t.agentReport.action}
                                onClick={() => onReport(message)}
                                className={cn(
                                    'shrink-0 rounded-full p-2 text-muted-foreground opacity-60 transition-opacity hover:opacity-100 focus-visible:opacity-100',
                                    message.isFinal
                                        ? 'animate-in fade-in delay-1000 duration-300 fill-mode-backwards'
                                        : 'invisible',
                                )}
                            >
                                <Icon name="flag" size={16} />
                            </button>
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
            return SHOW_TOOL_CARDS || debugEnabled ? (
                <ToolCard message={message} debugEnabled={debugEnabled} />
            ) : null
        case 'system':
            return <SystemLine message={message} />
        case 'action-result':
            return <ActionWidget message={message} />
    }
}

// Welcome view

type MicPhase = 'idle' | 'opening' | 'listening' | 'paused'
type BarMode = 'composer' | 'holding' | 'locked'

/**
 * The empty conversation, porting `_WelcomeView`: one line, the prompt
 * suggestions and the start button while idle, the app icon once the mic is
 * opening, listening or paused.
 */
function WelcomeView({
    phase,
    suggestions,
    onSuggestion,
    onStart,
    startDisabled,
}: {
    phase: MicPhase
    suggestions: { key: string; text: string }[]
    onSuggestion: (text: string) => void
    onStart: () => void
    startDisabled: boolean
}) {
    const t = useT()
    if (phase !== 'idle') {
        return (
            <div className="flex flex-1 flex-col items-center justify-center gap-4">
                <img src={appIcon} alt="" className="size-24 object-contain" />
                <p
                    className={cn(
                        'm3-title-medium',
                        phase === 'listening'
                            ? 'text-on-surface'
                            : 'text-on-surface-variant',
                    )}
                >
                    {phase === 'opening'
                        ? t.voice.preparingMic
                        : phase === 'paused'
                          ? t.voice.micPaused
                          : t.voice.listening}
                </p>
            </div>
        )
    }
    return (
        <div className="flex flex-1 flex-col items-center justify-center text-center">
            <span className="grid size-18 place-items-center rounded-full bg-secondary-container text-on-secondary-container">
                <AgentGlyph size={34} />
            </span>
            <h2 className="m3-headline-small mt-5 text-on-surface">
                {t.voice.welcomeTitle}
            </h2>
            <p className="m3-body-medium mt-2 max-w-xs text-on-surface-variant">
                {t.voice.welcome}
            </p>
            {suggestions.length > 0 && (
                <div className="mt-7 flex max-w-xl flex-wrap justify-center gap-2">
                    {suggestions.map((s) => (
                        <AssistChip
                            key={s.key}
                            label={s.text}
                            onPress={() => onSuggestion(s.text)}
                        />
                    ))}
                </div>
            )}
            <Button
                variant="filled"
                onPress={onStart}
                isDisabled={startDisabled}
                className="mt-7 h-14 px-7"
            >
                <Icon name="mic" filled size={20} />
                {t.voice.startTalking}
            </Button>
        </div>
    )
}

// Composer

/**
 * The text field of the control bar, porting `_TextComposer`: a single line
 * that grows to four before it scrolls. See `useEnterSends` for which Enter
 * sends and which breaks the line.
 */
function Composer({
    value,
    onChange,
    onSend,
    inputRef: ref,
}: {
    value: string
    onChange: (value: string) => void
    onSend: () => void
    inputRef: RefObject<HTMLTextAreaElement | null>
}) {
    const t = useT()
    const enterSends = useEnterSends()

    useEffect(() => {
        const el = ref.current
        if (!el) return
        // Collapse first, then measure the content — an empty composer is one
        // row, anything else grows up to the cap and scrolls past it.
        el.style.height = 'auto'
        if (value === '') return
        el.style.height = `${Math.min(el.scrollHeight, COMPOSER_MAX_HEIGHT)}px`
    }, [value, ref])

    const handleKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
        if (!enterSends(event)) return
        event.preventDefault()
        onSend()
    }

    return (
        <div className="flex min-h-12 min-w-0 flex-1 items-center rounded-3xl bg-surface-container-high px-4">
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

// Hold hint

/** Points at the composer's mic, so it is clear which mic can be held. */
function HoldHint() {
    const t = useT()
    return (
        <div className="flex flex-col items-end">
            <span className="m3-body-small rounded-lg bg-inverse-surface px-3 py-2 text-inverse-on-surface">
                {t.voice.holdHint}
            </span>
            {/* Centres the caret on the 48px mic button below. */}
            <span
                aria-hidden
                className="mr-[18px] size-0 border-x-[6px] border-t-[6px] border-x-transparent border-t-inverse-surface"
            />
        </div>
    )
}

// Mic button

/**
 * The composer's trailing button, porting `_MicButton`: a send arrow while
 * the composer holds text, otherwise the mic. Tap opens it hands-free, press
 * and hold talks, dragging up locks it. Pointer capture keeps the drag alive
 * once the finger leaves the button.
 */
function MicButton({
    holding,
    showSpinner,
    hasText,
    holdDrag,
    onTap,
    onSend,
    onHoldStart,
    onHoldMove,
    onHoldEnd,
}: {
    holding: boolean
    showSpinner: boolean
    hasText: boolean
    holdDrag: number
    onTap: () => void
    onSend: () => void
    onHoldStart: () => void
    onHoldMove: (dy: number) => void
    onHoldEnd: () => void
}) {
    const t = useT()
    const pointerRef = useRef<number | null>(null)
    const originRef = useRef(0)
    const heldRef = useRef(false)
    const suppressClickRef = useRef(false)
    const timerRef = useRef<number | null>(null)

    const clearTimer = useCallback(() => {
        if (timerRef.current === null) return
        window.clearTimeout(timerRef.current)
        timerRef.current = null
    }, [])

    useEffect(() => clearTimer, [clearTimer])

    const base =
        'grid size-12 shrink-0 place-items-center rounded-full bg-primary-container text-on-primary-container'

    if (hasText) {
        return (
            <button
                type="button"
                onClick={onSend}
                aria-label={t.voice.send}
                className={base}
            >
                <Icon name="arrow_upward" filled size={24} />
            </button>
        )
    }

    const handlePointerDown = (event: PointerEvent<HTMLButtonElement>) => {
        if (event.button !== 0 || pointerRef.current !== null) return
        pointerRef.current = event.pointerId
        originRef.current = event.clientY
        heldRef.current = false
        event.currentTarget.setPointerCapture(event.pointerId)
        timerRef.current = window.setTimeout(() => {
            timerRef.current = null
            heldRef.current = true
            onHoldStart()
        }, HOLD_MS)
    }

    const handlePointerMove = (event: PointerEvent<HTMLButtonElement>) => {
        if (event.pointerId !== pointerRef.current || !heldRef.current) return
        onHoldMove(event.clientY - originRef.current)
    }

    const handlePointerUp = (event: PointerEvent<HTMLButtonElement>) => {
        if (event.pointerId !== pointerRef.current) return
        pointerRef.current = null
        clearTimer()
        if (!heldRef.current) return
        heldRef.current = false
        suppressClickRef.current = true
        onHoldEnd()
    }

    // A tap acts on `click`, not on pointer up: acting on pointer up swaps in
    // the locked bar first, and the browser's click then lands on whatever
    // now sits under the finger, which is the switch-to-text button.
    const handleClick = () => {
        if (suppressClickRef.current) {
            suppressClickRef.current = false
            return
        }
        onTap()
    }

    const handlePointerCancel = (event: PointerEvent<HTMLButtonElement>) => {
        if (event.pointerId !== pointerRef.current) return
        pointerRef.current = null
        clearTimer()
        if (!heldRef.current) return
        heldRef.current = false
        onHoldEnd()
    }

    const handleKeyDown = (event: KeyboardEvent<HTMLButtonElement>) => {
        if (event.key !== 'Enter' && event.key !== ' ') return
        event.preventDefault()
        onTap()
    }

    return (
        <div className="relative shrink-0">
            {holding && <LockPill drag={holdDrag} />}
            <button
                type="button"
                aria-label={t.voice.startTalking}
                className={cn(
                    base,
                    'touch-none transition-transform duration-150 select-none',
                    holding && 'scale-[1.45] shadow-level-3',
                )}
                onClick={handleClick}
                onPointerDown={handlePointerDown}
                onPointerMove={handlePointerMove}
                onPointerUp={handlePointerUp}
                onPointerCancel={handlePointerCancel}
                onKeyDown={handleKeyDown}
                onContextMenu={(event) => event.preventDefault()}
                // Clicking the mic must not pull focus out of the composer.
                onMouseDown={(event) => event.preventDefault()}
            >
                {showSpinner ? (
                    <CircularProgress isIndeterminate size="xs" />
                ) : (
                    <Icon name="mic" filled size={24} />
                )}
            </button>
        </div>
    )
}

function LockPill({ drag }: { drag: number }) {
    const locked = -drag / LOCK_DISTANCE > 0.6
    return (
        <div
            aria-hidden
            className="absolute bottom-[calc(100%+24px)] left-1/2 flex flex-col items-center gap-1.5 rounded-full bg-surface-container-high px-2 py-2.5 text-on-surface-variant shadow-level-2"
            style={{ transform: `translate(-50%, ${drag * 0.6}px)` }}
        >
            <Icon name={locked ? 'lock' : 'lock_open'} size={22} />
            <Icon name="keyboard_arrow_up" size={22} />
        </div>
    )
}

// Recording strip

/**
 * The left side of the bar while the mic is open. One component for both the
 * hold and the locked layouts, at the same place in the tree, so the timer
 * keeps counting when a hold turns into a lock.
 */
function RecordingStrip({
    variant,
    phase,
    level,
}: {
    variant: 'holding' | 'locked'
    phase: MicPhase
    level: number
}) {
    const t = useT()
    const listening = phase === 'listening'
    return (
        <div
            className={cn(
                'flex h-12 min-w-0 items-center gap-2.5',
                variant === 'holding'
                    ? 'rounded-3xl bg-surface-container-high px-4'
                    : 'px-2',
            )}
        >
            {variant === 'locked' && phase === 'opening' ? (
                <CircularProgress isIndeterminate size="xs" />
            ) : variant === 'holding' ? (
                <Icon
                    name="mic"
                    filled
                    size={20}
                    className={cn(
                        'shrink-0',
                        listening
                            ? 'text-error motion-safe:animate-pulse'
                            : 'text-on-surface-variant',
                    )}
                />
            ) : (
                <span
                    className={cn(
                        'size-2.5 shrink-0 rounded-full',
                        listening
                            ? 'bg-error motion-safe:animate-pulse'
                            : 'bg-on-surface-variant',
                    )}
                />
            )}
            <RecordingTimer running={listening} />
            {variant === 'holding' ? (
                <span className="ml-auto flex min-w-0 items-center gap-1 text-on-surface-variant">
                    <Icon name="keyboard_arrow_up" size={18} />
                    <span className="m3-body-medium truncate">
                        {t.voice.slideToLock}
                    </span>
                </span>
            ) : (
                <Waveform level={level} running={listening} />
            )}
        </div>
    )
}

function RecordingTimer({ running }: { running: boolean }) {
    const accumulatedRef = useRef(0)
    const [seconds, setSeconds] = useState(0)

    useEffect(() => {
        if (!running) return
        const startedAt = Date.now()
        const id = window.setInterval(() => {
            setSeconds(
                Math.floor(
                    (accumulatedRef.current + Date.now() - startedAt) / 1000,
                ),
            )
        }, 250)
        return () => {
            window.clearInterval(id)
            accumulatedRef.current += Date.now() - startedAt
        }
    }, [running])

    return (
        <span className="m3-body-large shrink-0 text-on-surface tabular-nums">
            {Math.floor(seconds / 60)}:{String(seconds % 60).padStart(2, '0')}
        </span>
    )
}

/** The last few seconds of mic level, newest on the right. */
function Waveform({ level, running }: { level: number; running: boolean }) {
    const levelRef = useRef(level)
    const [levels, setLevels] = useState<number[]>(() =>
        Array.from({ length: WAVEFORM_BARS }, () => 0),
    )

    useEffect(() => {
        levelRef.current = level
    }, [level])

    useEffect(() => {
        if (!running) return
        const id = window.setInterval(() => {
            setLevels((prev) => [...prev.slice(1), levelRef.current])
        }, 100)
        return () => window.clearInterval(id)
    }, [running])

    return (
        <div
            aria-hidden
            className="flex h-8 min-w-0 flex-1 items-center justify-end gap-[3px] overflow-hidden"
        >
            {levels.map((value, i) => (
                <span
                    key={i}
                    className="w-[3px] shrink-0 rounded-full bg-on-surface-variant"
                    style={{ height: Math.max(3, Math.round(value * 32)) }}
                />
            ))}
        </div>
    )
}

// Locked controls

function LockedControls({
    paused,
    canPause,
    canResume,
    onPause,
    onResume,
    onSwitchToText,
}: {
    paused: boolean
    canPause: boolean
    canResume: boolean
    onPause: () => void
    onResume: () => void
    onSwitchToText: () => void
}) {
    const t = useT()
    const pill =
        'm3-label-large m3-state-layer flex h-12 flex-1 cursor-pointer items-center justify-center gap-2 rounded-full disabled:cursor-default disabled:opacity-40'
    return (
        <div className="flex items-center gap-2">
            {paused ? (
                <button
                    type="button"
                    onClick={onResume}
                    disabled={!canResume}
                    className={cn(pill, 'bg-primary text-on-primary')}
                >
                    <Icon name="mic" filled size={20} />
                    {t.voice.resume}
                </button>
            ) : (
                <button
                    type="button"
                    onClick={onPause}
                    disabled={!canPause}
                    className={cn(
                        pill,
                        'bg-surface-container-highest text-on-surface',
                    )}
                >
                    <Icon name="pause" filled size={20} />
                    {t.voice.pause}
                </button>
            )}
            <button
                type="button"
                onClick={onSwitchToText}
                aria-label={t.voice.switchToText}
                title={t.voice.switchToText}
                className="m3-state-layer grid size-12 shrink-0 cursor-pointer place-items-center rounded-full bg-primary-container text-on-primary-container"
            >
                <Icon name="chat" filled size={24} />
            </button>
        </div>
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
    const suggestionsEnabled = flags?.agentPromptSuggestions ?? false
    const promptSuggestions = usePromptSuggestions(suggestionsEnabled)
    const formatLocale = useFormatLocale()
    const [reportTarget, setReportTarget] = useState<ReportTarget | null>(null)
    const [reportSession, setReportSession] = useState<{
        sessionId?: string
        model?: string
    }>({})

    const [text, setText] = useState('')
    const isComposing = text.trim().length > 0
    const composerRef = useRef<HTMLTextAreaElement>(null)

    const [handsFree, setHandsFree] = useState(false)
    const [holding, setHolding] = useState(false)
    const [paused, setPaused] = useState(false)
    const [openingMic, setOpeningMic] = useState(false)
    const [holdDrag, setHoldDrag] = useState(0)

    // Native's `screen_attached` / `screen_detached`, with the same effects:
    // leaving mutes the mic and interrupts the answer in flight, and keeps
    // everything else running. The composer draft stays page-local, as
    // `_textController` does on native.
    const { attach, detach } = voice
    useEffect(() => {
        attach()
        return detach
    }, [attach, detach])

    // Mirrors native's `_MicPhase` and `_BarMode`: derived from the session's
    // own mic state, so a failed open or a dropped capture hides the bar.
    const isListening =
        voice.isMicCaptureActive && voice.isMicOn && !isComposing
    const phase: MicPhase = paused
        ? 'paused'
        : isListening
          ? 'listening'
          : openingMic || (voice.isConnecting && (handsFree || holding))
            ? 'opening'
            : 'idle'
    const barMode: BarMode = holding
        ? 'holding'
        : paused ||
            voice.isMicCaptureActive ||
            openingMic ||
            (handsFree && voice.isConnecting)
          ? 'locked'
          : 'composer'

    const bottomRef = useRef<HTMLDivElement>(null)
    useEffect(() => {
        if (voice.messages.length === 0) return
        bottomRef.current?.scrollIntoView({
            behavior: 'smooth',
            block: 'end',
        })
    }, [voice.messages])

    const handleTextChange = (next: string) => {
        const startedComposing = next.trim().length > 0 && !isComposing
        setText(next)
        voice.setComposing(next.trim().length > 0)
        // The hidden composer keeps the keyboard up while the mic is open, so
        // typing there is the same as the switch-to-text button.
        if (startedComposing && barMode !== 'composer') {
            setHolding(false)
            handleSwitchToText()
        }
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
        if (voice.isConnecting) {
            voice.setMicOn(false)
            return
        }
        if (isComposing) return
        if (!voice.isConnected) {
            startVoiceSession()
            return
        }
        if (!voice.isMicCaptureActive) {
            openMic()
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
            openMic()
            return
        }
        voice.setMicOn(true)
    }

    const handleLongPressEnd = () => {
        voice.releaseMic()
    }

    /** `voice.openMic`, tracked so the bar can show it opening. */
    const openMic = () => {
        setOpeningMic(true)
        void voice.openMic({ turnOn: true }).finally(() => setOpeningMic(false))
    }

    // The controls of the welcome view and the recording bar. They only drive
    // the UI state and delegate every microphone action to the handlers above.

    const handleMicPress = () => {
        if (isComposing) return
        if (!voice.isConnecting) {
            setHandsFree(true)
            setPaused(false)
        }
        handleTap()
    }

    const handleHoldStart = () => {
        if (voice.isConnecting || isComposing) return
        setHoldDrag(0)
        setHolding(true)
        setPaused(false)
        handleLongPressStart()
    }

    const handleHoldMove = (dy: number) => {
        if (!holding) return
        setHoldDrag(Math.max(-LOCK_DISTANCE, Math.min(0, dy)))
        if (dy > -LOCK_DISTANCE) return
        setHolding(false)
        setHandsFree(true)
    }

    const handleHoldEnd = () => {
        if (!holding) return
        setHolding(false)
        handleLongPressEnd()
    }

    const handlePause = () => {
        setPaused(true)
        handleTap()
    }

    const handleResume = () => {
        setPaused(false)
        handleTap()
    }

    /**
     * Not `handleTap`: a tap would reopen a mic that is still opening, and it
     * does nothing once the composer holds text.
     */
    const handleSwitchToText = () => {
        setHandsFree(false)
        setPaused(false)
        if (voice.isConnecting || openingMic || voice.isMicCaptureActive) {
            voice.setMicOn(false)
        }
    }

    const handleComposerSend = () => {
        setHandsFree(false)
        handleSend()
    }

    const handleEnd = () => {
        setHandsFree(false)
        setHolding(false)
        setPaused(false)
        voice.disconnect()
    }

    const handleSuggestion = (suggestion: string) => {
        handleTextChange(suggestion)
        composerRef.current?.focus()
    }

    const suggestions = promptSuggestions.map((s) => ({
        key: promptSuggestionKey(s),
        text: suggestionText(t, formatLocale, s),
    }))

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
                        {voice.isConnected && (
                            <IconButton
                                aria-label={t.voice.endSession}
                                onPress={handleEnd}
                                className="text-error"
                            >
                                <Icon name="call_end" filled />
                            </IconButton>
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
                    <WelcomeView
                        phase={phase}
                        suggestions={suggestions}
                        onSuggestion={handleSuggestion}
                        onStart={handleMicPress}
                        startDisabled={isComposing}
                    />
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

            <div className="shrink-0 bg-surface px-3 py-2">
                <div className="mx-auto flex max-w-2xl flex-col gap-2">
                    {voice.messages.length === 0 &&
                        barMode === 'composer' &&
                        phase === 'idle' &&
                        !isComposing && <HoldHint />}
                    <div className="flex items-end gap-2">
                        <div className="relative min-w-0 flex-1">
                            {/* Hidden, not unmounted, while the mic is open:
                                the textarea keeps its focus and the keyboard. */}
                            <div
                                className={
                                    barMode === 'composer'
                                        ? undefined
                                        : 'sr-only'
                                }
                            >
                                <Composer
                                    value={text}
                                    onChange={handleTextChange}
                                    onSend={handleComposerSend}
                                    inputRef={composerRef}
                                />
                            </div>
                            {barMode !== 'composer' && (
                                <RecordingStrip
                                    variant={
                                        barMode === 'holding'
                                            ? 'holding'
                                            : 'locked'
                                    }
                                    phase={phase}
                                    level={voice.micLevel}
                                />
                            )}
                        </div>
                        {barMode !== 'locked' && (
                            <MicButton
                                holding={barMode === 'holding'}
                                showSpinner={
                                    voice.isConnecting &&
                                    !voice.isMicCaptureActive
                                }
                                hasText={isComposing}
                                holdDrag={holdDrag}
                                onTap={handleMicPress}
                                onSend={handleComposerSend}
                                onHoldStart={handleHoldStart}
                                onHoldMove={handleHoldMove}
                                onHoldEnd={handleHoldEnd}
                            />
                        )}
                    </div>
                    {barMode === 'locked' && (
                        <LockedControls
                            paused={phase === 'paused'}
                            canPause={
                                voice.isConnected &&
                                voice.isMicCaptureActive &&
                                voice.isMicOn
                            }
                            canResume={!voice.isConnecting && !openingMic}
                            onPause={handlePause}
                            onResume={handleResume}
                            onSwitchToText={handleSwitchToText}
                        />
                    )}
                </div>
            </div>
        </>
    )
}
