import {
    ArrowDownRight,
    AudioLines,
    CircleAlert,
    Info,
    Mic,
    MicOff,
    Phone,
    PhoneOff,
    Trash2,
    Wrench,
} from 'lucide-react'
import { useEffect, useRef } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
    Card,
    CardAction,
    CardContent,
    CardHeader,
    CardTitle,
} from '@/components/ui/card'
import { useVoice, type VoiceLogEntry } from '@/hooks/use-voice'
import { cn } from '@/lib/utils'

// ── Log entry rendering ──────────────────────────────────────

const LOG_ICON: Record<VoiceLogEntry['type'], React.ReactNode> = {
    info: <Info className="size-3.5 text-muted-foreground" />,
    'tool-call': <Wrench className="size-3.5 text-blue-500" />,
    'tool-response': <ArrowDownRight className="size-3.5 text-green-500" />,
    audio: <AudioLines className="size-3.5 text-muted-foreground" />,
    error: <CircleAlert className="size-3.5 text-destructive" />,
}

function LogLine({ entry }: { entry: VoiceLogEntry }) {
    const time = entry.timestamp.toLocaleTimeString('en-US', {
        hour12: false,
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
    })

    return (
        <div className="flex items-start gap-2 py-1 font-mono text-xs">
            <span className="shrink-0 text-muted-foreground">{time}</span>
            <span className="mt-px shrink-0">{LOG_ICON[entry.type]}</span>
            <span
                className={cn(
                    'break-all',
                    entry.type === 'error' && 'text-destructive',
                )}
            >
                {entry.message}
            </span>
            {entry.detail !== undefined && (
                <span className="ml-auto shrink-0 text-muted-foreground">
                    {JSON.stringify(entry.detail).slice(0, 120)}
                </span>
            )}
        </div>
    )
}

// ── Status badge ─────────────────────────────────────────────

function StatusBadge({ status }: { status: string }) {
    const variant =
        status === 'connected'
            ? 'default'
            : status === 'connecting'
              ? 'secondary'
              : 'outline'

    return <Badge variant={variant}>{status}</Badge>
}

// ── Page ─────────────────────────────────────────────────────

export default function Home() {
    const voice = useVoice()
    const logEndRef = useRef<HTMLDivElement>(null)

    useEffect(() => {
        if (voice.logs.length > 0) {
            logEndRef.current?.scrollIntoView({ behavior: 'smooth' })
        }
    }, [voice.logs])

    return (
        <div className="mx-auto flex max-w-2xl flex-col gap-4 p-4">
            {/* Controls */}
            <Card>
                <CardHeader>
                    <CardTitle>Live Voice</CardTitle>
                    <CardAction>
                        <StatusBadge status={voice.connectionStatus} />
                    </CardAction>
                </CardHeader>
                <CardContent className="flex flex-col gap-3">
                    {/* Connection */}
                    <div className="flex items-center gap-2">
                        {!voice.isConnected ? (
                            <Button
                                onClick={voice.connect}
                                disabled={voice.isConnecting}
                            >
                                <Phone
                                    className="size-4"
                                    data-icon="inline-start"
                                />
                                {voice.isConnecting
                                    ? 'Connecting...'
                                    : 'Connect'}
                            </Button>
                        ) : (
                            <Button
                                variant="destructive"
                                onClick={voice.disconnect}
                            >
                                <PhoneOff
                                    className="size-4"
                                    data-icon="inline-start"
                                />
                                Disconnect
                            </Button>
                        )}

                        {/* Mute */}
                        {voice.isConnected && (
                            <Button
                                variant={
                                    voice.isMuted ? 'outline' : 'secondary'
                                }
                                onClick={() => voice.setIsMuted(!voice.isMuted)}
                            >
                                {voice.isMuted ? (
                                    <MicOff
                                        className="size-4"
                                        data-icon="inline-start"
                                    />
                                ) : (
                                    <Mic
                                        className="size-4"
                                        data-icon="inline-start"
                                    />
                                )}
                                {voice.isMuted ? 'Unmute' : 'Mute'}
                            </Button>
                        )}
                    </div>

                    {/* Mic level */}
                    {voice.isConnected && (
                        <div className="flex items-center gap-2">
                            <span className="text-xs text-muted-foreground">
                                Mic level
                            </span>
                            <div className="h-2 flex-1 overflow-hidden rounded-full bg-muted">
                                <div
                                    className="h-full bg-green-500 transition-all duration-75"
                                    style={{
                                        width: `${Math.round(voice.micLevel * 100)}%`,
                                    }}
                                />
                            </div>
                        </div>
                    )}

                    {/* Device selector */}
                    {voice.isConnected && voice.devices.length > 1 && (
                        <select
                            className="rounded-md border bg-background px-2 py-1.5 text-sm"
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
                </CardContent>
            </Card>

            {/* Event log */}
            <Card>
                <CardHeader>
                    <CardTitle>Event Log</CardTitle>
                    <CardAction>
                        <Button
                            variant="ghost"
                            size="icon-xs"
                            onClick={voice.clearLogs}
                            disabled={voice.logs.length === 0}
                        >
                            <Trash2 className="size-3.5" />
                        </Button>
                    </CardAction>
                </CardHeader>
                <CardContent>
                    <div className="h-80 overflow-y-auto rounded-md border bg-muted/30 p-2">
                        {voice.logs.length === 0 ? (
                            <p className="py-8 text-center text-sm text-muted-foreground">
                                No events yet. Connect to start.
                            </p>
                        ) : (
                            voice.logs.map((entry) => (
                                <LogLine key={entry.id} entry={entry} />
                            ))
                        )}
                        <div ref={logEndRef} />
                    </div>
                </CardContent>
            </Card>
        </div>
    )
}
