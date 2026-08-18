import { api } from '@wallet-bot/backend/api'
import { useConvex, useQuery } from 'convex/react'
import {
    AlertCircle,
    CheckCircle2,
    Hourglass,
    Info,
    Mic,
    MicOff,
    Phone,
    PhoneOff,
    Sparkles,
    Wrench,
    XCircle,
} from 'lucide-react'
import { useEffect, useRef } from 'react'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'
import { type ChatMessage, useVoice } from '@/hooks/use-voice'
import { useFormatLocale, useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'
import { ActionWidget } from '@/pages/add-action-widget'

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
                <div className="rounded-2xl rounded-br-sm bg-primary px-4 py-2.5 text-primary-foreground">
                    {text && (
                        <p className="whitespace-pre-wrap text-sm leading-snug">
                            {text}
                        </p>
                    )}
                    {!message.isFinal && (
                        <div
                            className={cn(
                                'text-primary-foreground/70',
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
}: {
    message: Extract<ChatMessage, { kind: 'agent' }>
}) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const text = message.text.trim()
    return (
        <div className="flex justify-start">
            <div className="flex max-w-[82%] items-start gap-2">
                <Avatar size="sm" className="mt-5 size-7">
                    <AvatarFallback className="bg-secondary text-secondary-foreground">
                        <Sparkles className="size-3.5" />
                    </AvatarFallback>
                </Avatar>
                <div className="flex flex-col items-start gap-1">
                    <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                        <span className="font-medium">{t.voice.agent}</span>
                        <span>{formatTime(message.at, formatLocale)}</span>
                    </div>
                    <div className="rounded-2xl rounded-tl-sm bg-muted px-4 py-2.5 text-foreground">
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
    const StatusIcon =
        status === 'pending'
            ? Hourglass
            : status === 'completed'
              ? CheckCircle2
              : XCircle
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
                    <Wrench className="size-3.5 text-muted-foreground" />
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
                        <StatusIcon className="size-3.5" />
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
    const Icon =
        message.level === 'error'
            ? AlertCircle
            : message.level === 'success'
              ? CheckCircle2
              : Info
    const color =
        message.level === 'error'
            ? 'text-destructive'
            : message.level === 'success'
              ? 'text-primary'
              : 'text-muted-foreground'
    return (
        <div className="flex justify-center">
            <div className={cn('flex items-center gap-1.5 text-xs', color)}>
                <Icon className="size-3.5" />
                <span>{message.message}</span>
            </div>
        </div>
    )
}

function MessageView({
    message,
    debugEnabled,
}: {
    message: ChatMessage
    debugEnabled: boolean
}) {
    switch (message.kind) {
        case 'user':
            return <UserBubble message={message} />
        case 'agent':
            return <AgentBubble message={message} />
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
              ? 'border-amber-500 text-amber-600 dark:text-amber-400'
              : 'border-muted-foreground/40 text-muted-foreground'
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
            <Mic className="size-12 opacity-50" />
            <p className="text-sm">
                {isConnecting ? t.voice.connectingEllipsis : t.voice.tapToStart}
            </p>
        </div>
    )
}

// Page

export function Add() {
    const t = useT()
    const client = useConvex()
    const voice = useVoice({ context: { client } })
    const flags = useQuery(api.v1.featureFlags.queries.getMyFlags)
    const debugEnabled = flags?.debugToolCalls ?? false

    const status: 'idle' | 'connecting' | 'connected' = voice.isConnected
        ? 'connected'
        : voice.isConnecting
          ? 'connecting'
          : 'idle'

    const bottomRef = useRef<HTMLDivElement>(null)
    useEffect(() => {
        if (voice.messages.length === 0) return
        bottomRef.current?.scrollIntoView({
            behavior: 'smooth',
            block: 'end',
        })
    }, [voice.messages])

    return (
        <div className="flex flex-1 flex-col">
            {/* Sub-header with status */}
            <div className="flex items-center justify-between gap-2 border-b bg-background/50 px-4 py-2">
                <h2 className="text-sm font-medium">{t.voice.title}</h2>
                <StatusPill status={status} />
            </div>

            {/* Messages — natural flow, footer is sticky over them */}
            <div className="flex flex-1 flex-col gap-3 px-4 py-6 pb-40">
                {voice.messages.length === 0 ? (
                    <EmptyState isConnecting={voice.isConnecting} />
                ) : (
                    voice.messages.map((m) => (
                        <MessageView
                            key={m.id}
                            message={m}
                            debugEnabled={debugEnabled}
                        />
                    ))
                )}
                <div ref={bottomRef} aria-hidden className="h-0" />
            </div>

            {/* Control bar — sticky at bottom of scroll container */}
            <div className="sticky bottom-0 z-10 border-t bg-background/95 px-4 py-3 backdrop-blur supports-backdrop-filter:bg-background/75">
                <div className="mx-auto flex max-w-2xl flex-col gap-3">
                    {/* Mic level */}
                    {voice.isConnected && (
                        <div className="h-1 overflow-hidden rounded-full bg-muted">
                            <div
                                className={cn(
                                    'h-full transition-all duration-75',
                                    voice.isMuted ? 'bg-muted' : 'bg-primary',
                                )}
                                style={{
                                    width: `${Math.round((voice.isMuted ? 0 : voice.micLevel) * 100)}%`,
                                }}
                            />
                        </div>
                    )}

                    <div className="flex items-center justify-center gap-3">
                        {voice.isConnected && (
                            <Button
                                type="button"
                                variant="outline"
                                size="icon-lg"
                                onClick={() => voice.setIsMuted(!voice.isMuted)}
                                aria-label={
                                    voice.isMuted
                                        ? t.voice.unmute
                                        : t.voice.mute
                                }
                                className={cn(
                                    'rounded-full',
                                    voice.isMuted &&
                                        'border-destructive text-destructive',
                                )}
                            >
                                {voice.isMuted ? (
                                    <MicOff className="size-5" />
                                ) : (
                                    <Mic className="size-5" />
                                )}
                            </Button>
                        )}

                        {voice.isConnected ? (
                            <Button
                                type="button"
                                size="icon-lg"
                                variant="destructive"
                                onClick={voice.disconnect}
                                aria-label={t.voice.disconnect}
                                className="size-14 rounded-full"
                            >
                                <PhoneOff className="size-6" />
                            </Button>
                        ) : (
                            <Button
                                type="button"
                                size="icon-lg"
                                onClick={voice.connect}
                                disabled={voice.isConnecting}
                                aria-label={t.voice.connect}
                                className="size-14 rounded-full"
                            >
                                <Phone className="size-6" />
                            </Button>
                        )}
                    </div>

                    {/* Device selector */}
                    {voice.isConnected && voice.devices.length > 1 && (
                        <select
                            className="mx-auto w-full max-w-xs rounded-md border bg-background px-2 py-1.5 text-xs"
                            value={voice.selectedDeviceId}
                            onChange={(e) =>
                                voice.handleDeviceChange(e.target.value)
                            }
                        >
                            {voice.devices.map((d) => (
                                <option key={d.deviceId} value={d.deviceId}>
                                    {d.label || d.deviceId}
                                </option>
                            ))}
                        </select>
                    )}
                </div>
            </div>
        </div>
    )
}
