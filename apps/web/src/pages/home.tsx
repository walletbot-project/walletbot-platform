import { api } from '@wallet-bot/backend/api'
import { useConvex, useMutation, useQuery } from 'convex/react'
import { format } from 'date-fns'
import {
    ChevronDown,
    LogOut,
    Mic,
    MicOff,
    Phone,
    PhoneOff,
    Plus,
    Trash2,
} from 'lucide-react'
import { useCallback, useEffect, useRef, useState } from 'react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle,
} from '@/components/ui/card'
import {
    Dialog,
    DialogClose,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
    DialogTrigger,
} from '@/components/ui/dialog'
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuGroup,
    DropdownMenuLabel,
    DropdownMenuRadioGroup,
    DropdownMenuRadioItem,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Input } from '@/components/ui/input'
import { useAuth, useUser } from '@/hooks/use-auth'
import {
    EXPENSE_SYSTEM_INSTRUCTION,
    executeToolCall,
    expenseToolDeclarations,
} from '@/lib/expense-tools'

// ── Constants ─────────────────────────────────────────────────

const CATEGORIES = [
    'groceries',
    'transport',
    'dining',
    'entertainment',
    'utilities',
    'health',
    'shopping',
    'other',
] as const

const CATEGORY_COLORS: Record<string, string> = {
    groceries:
        'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
    transport: 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200',
    dining: 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200',
    entertainment:
        'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200',
    utilities: 'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200',
    health: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200',
    shopping: 'bg-pink-100 text-pink-800 dark:bg-pink-900 dark:text-pink-200',
    other: 'bg-muted text-muted-foreground',
}

// ── Audio helpers ─────────────────────────────────────────────

const INPUT_SAMPLE_RATE = 16000
const OUTPUT_SAMPLE_RATE = 24000

const WS_BASE_URL =
    'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained'

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

// ── Main page ─────────────────────────────────────────────────

export function Home() {
    const user = useUser()
    const { signOut } = useAuth()

    return (
        <div className="flex min-h-screen flex-col bg-background">
            <header className="flex items-center justify-between border-b px-4 py-3">
                <div className="flex items-center gap-3">
                    <h1 className="text-lg font-semibold tracking-tight">
                        Wallet Bot
                    </h1>
                    <span className="text-sm text-muted-foreground">
                        {user.name}
                    </span>
                </div>
                <Button variant="ghost" size="sm" onClick={() => signOut()}>
                    <LogOut className="size-4" />
                    Sign out
                </Button>
            </header>

            <main className="flex flex-1 items-start justify-center p-4">
                <div className="w-full max-w-lg">
                    <ExpensesCard />
                </div>
            </main>
        </div>
    )
}

// ── useVoice hook ─────────────────────────────────────────────

type ConnectionStatus = 'disconnected' | 'connecting' | 'connected'

function useVoice() {
    const convex = useConvex()

    const [connectionStatus, setConnectionStatus] =
        useState<ConnectionStatus>('disconnected')
    const [isMuted, setIsMuted] = useState(false)
    const [micLevel, setMicLevel] = useState(0)
    const [devices, setDevices] = useState<MediaDeviceInfo[]>([])
    const [selectedDeviceId, setSelectedDeviceId] = useState<string>('')

    const wsRef = useRef<WebSocket | null>(null)
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

        try {
            const tempStream = await navigator.mediaDevices.getUserMedia({
                audio: true,
            })
            for (const track of tempStream.getTracks()) track.stop()
            await refreshDevicesRef.current()

            const { token, model } = await convex.action(
                api.live.actions.requestLiveToken,
                {},
            )

            const ws = new WebSocket(`${WS_BASE_URL}?access_token=${token}`)
            wsRef.current = ws

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

            ws.onopen = () => {
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

                if (msg.setupComplete) {
                    setConnectionStatus('connected')
                    startMicCapture(selectedDeviceIdRef.current)
                    return
                }

                if (msg.toolCall) {
                    const functionCalls: {
                        id: string
                        name: string
                        args: Record<string, unknown>
                    }[] = msg.toolCall.functionCalls ?? []

                    const functionResponses = []
                    for (const fc of functionCalls) {
                        const result = await executeToolCall(
                            convex,
                            fc.name,
                            fc.args,
                        )
                        functionResponses.push({
                            id: fc.id,
                            name: fc.name,
                            response: { result },
                        })
                    }

                    ws.send(
                        JSON.stringify({
                            toolResponse: { functionResponses },
                        }),
                    )
                    return
                }

                if (msg.toolCallCancellation) return

                const serverContent = msg.serverContent
                const parts = serverContent?.modelTurn?.parts
                if (parts) {
                    for (const part of parts) {
                        if (part.inlineData?.data) {
                            const float32 = base64ToPcmFloat32(
                                part.inlineData.data,
                            )
                            playbackNode.port.postMessage(float32)
                        }
                    }
                }

                if (serverContent?.interrupted) {
                    playbackNode.port.postMessage('interrupt')
                }
            }

            ws.onerror = () => {
                setConnectionStatus('disconnected')
            }

            ws.onclose = () => {
                setConnectionStatus('disconnected')
                setMicLevel(0)
            }
        } catch {
            setConnectionStatus('disconnected')
        }
    }, [convex, startMicCapture])

    // ── Disconnect ────────────────────────────────────────────

    const disconnect = useCallback(() => {
        stopMicCapture()

        playbackWorkletRef.current?.disconnect()
        playbackContextRef.current?.close()

        wsRef.current?.close()

        playbackWorkletRef.current = null
        playbackContextRef.current = null
        wsRef.current = null

        setConnectionStatus('disconnected')
    }, [stopMicCapture])

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
    }
}

// ── Expenses card ─────────────────────────────────────────────

function ExpensesCard() {
    const voice = useVoice()

    const expenses = useQuery(api.expenses.queries.listExpensesByDateRange, {
        startDate: '2000-01-01',
        endDate: '2099-12-31',
    })
    const addExpense = useMutation(api.expenses.mutations.addExpense)
    const deleteExpense = useMutation(api.expenses.mutations.deleteExpense)

    const [dialogOpen, setDialogOpen] = useState(false)
    const [amount, setAmount] = useState('')
    const [description, setDescription] = useState('')
    const [category, setCategory] = useState<string>('other')
    const [date, setDate] = useState(() => format(new Date(), 'yyyy-MM-dd'))
    const [submitting, setSubmitting] = useState(false)

    const handleAdd = async () => {
        const parsed = Number.parseFloat(amount)
        if (!parsed || parsed <= 0 || !description.trim()) return

        setSubmitting(true)
        await addExpense({
            amount: Math.round(parsed * 100),
            description: description.trim(),
            category,
            date,
        })

        setAmount('')
        setDescription('')
        setCategory('other')
        setDate(format(new Date(), 'yyyy-MM-dd'))
        setDialogOpen(false)
        setSubmitting(false)
    }

    const handleDelete = async (expenseId: string) => {
        await deleteExpense({ expenseId })
    }

    const loading = expenses === undefined
    const totalCents = expenses?.reduce((sum, e) => sum + e.amount, 0) ?? 0

    return (
        <Card>
            <CardHeader>
                <div className="flex items-center justify-between">
                    <div>
                        <CardTitle>Expenses</CardTitle>
                        <CardDescription>
                            Total: ${(totalCents / 100).toFixed(2)} across{' '}
                            {expenses?.length ?? 0} expenses
                        </CardDescription>
                    </div>
                    <div className="flex items-center gap-1.5">
                        {/* Voice controls */}
                        {voice.isConnected ? (
                            <>
                                <Button
                                    variant={
                                        voice.isMuted ? 'secondary' : 'outline'
                                    }
                                    size="icon-xs"
                                    onClick={() => voice.setIsMuted((m) => !m)}
                                >
                                    {voice.isMuted ? (
                                        <MicOff className="size-3.5" />
                                    ) : (
                                        <Mic className="size-3.5" />
                                    )}
                                </Button>
                                <Button
                                    variant="destructive"
                                    size="sm"
                                    onClick={voice.disconnect}
                                >
                                    <PhoneOff className="size-3.5" />
                                    End
                                </Button>
                            </>
                        ) : (
                            <Button
                                size="sm"
                                variant="outline"
                                onClick={voice.connect}
                                disabled={voice.isConnecting}
                            >
                                <Phone className="size-3.5" />
                                {voice.isConnecting ? 'Connecting...' : 'Voice'}
                            </Button>
                        )}

                        {/* Add expense */}
                        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
                            <DialogTrigger>
                                <Button size="sm">
                                    <Plus />
                                    Add
                                </Button>
                            </DialogTrigger>
                            <DialogContent>
                                <DialogHeader>
                                    <DialogTitle>Add Expense</DialogTitle>
                                    <DialogDescription>
                                        Add a new expense to your tracker.
                                    </DialogDescription>
                                </DialogHeader>
                                <div className="flex flex-col gap-3">
                                    <div className="flex flex-col gap-1">
                                        <label
                                            htmlFor="expense-amount"
                                            className="text-sm font-medium"
                                        >
                                            Amount ($)
                                        </label>
                                        <Input
                                            id="expense-amount"
                                            type="number"
                                            step="0.01"
                                            min="0.01"
                                            placeholder="0.00"
                                            value={amount}
                                            onChange={(e) =>
                                                setAmount(e.target.value)
                                            }
                                        />
                                    </div>
                                    <div className="flex flex-col gap-1">
                                        <label
                                            htmlFor="expense-description"
                                            className="text-sm font-medium"
                                        >
                                            Description
                                        </label>
                                        <Input
                                            id="expense-description"
                                            placeholder="What was it for?"
                                            value={description}
                                            onChange={(e) =>
                                                setDescription(e.target.value)
                                            }
                                        />
                                    </div>
                                    <div className="flex flex-col gap-1">
                                        <span className="text-sm font-medium">
                                            Category
                                        </span>
                                        <div className="flex flex-wrap gap-1">
                                            {CATEGORIES.map((c) => (
                                                <button
                                                    key={c}
                                                    type="button"
                                                    onClick={() =>
                                                        setCategory(c)
                                                    }
                                                    className={`rounded-md px-2 py-1 text-xs capitalize transition-colors ${
                                                        category === c
                                                            ? 'ring-2 ring-ring ring-offset-1'
                                                            : ''
                                                    } ${CATEGORY_COLORS[c]}`}
                                                >
                                                    {c}
                                                </button>
                                            ))}
                                        </div>
                                    </div>
                                    <div className="flex flex-col gap-1">
                                        <label
                                            htmlFor="expense-date"
                                            className="text-sm font-medium"
                                        >
                                            Date
                                        </label>
                                        <Input
                                            id="expense-date"
                                            type="date"
                                            value={date}
                                            onChange={(e) =>
                                                setDate(e.target.value)
                                            }
                                        />
                                    </div>
                                </div>
                                <DialogFooter>
                                    <DialogClose>
                                        <Button variant="outline">
                                            Cancel
                                        </Button>
                                    </DialogClose>
                                    <Button
                                        onClick={handleAdd}
                                        disabled={
                                            submitting ||
                                            !amount ||
                                            !description.trim()
                                        }
                                    >
                                        {submitting
                                            ? 'Adding...'
                                            : 'Add Expense'}
                                    </Button>
                                </DialogFooter>
                            </DialogContent>
                        </Dialog>
                    </div>
                </div>
            </CardHeader>

            {/* Mic strip — only visible when connected */}
            {voice.isConnected && (
                <div className="flex items-center gap-2 border-t px-6 py-2">
                    {/* Level meter */}
                    <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-muted">
                        <div
                            className="h-full rounded-full bg-green-500 transition-[width] duration-75"
                            style={{ width: `${voice.micLevel * 100}%` }}
                        />
                    </div>

                    {/* Mic picker */}
                    <DropdownMenu>
                        <DropdownMenuTrigger className="inline-flex h-6 items-center gap-1 rounded-md px-1.5 text-xs text-muted-foreground hover:bg-accent hover:text-accent-foreground">
                            <Mic className="size-3" />
                            <span className="max-w-28 truncate">
                                {voice.devices.find(
                                    (d) =>
                                        d.deviceId === voice.selectedDeviceId,
                                )?.label || 'Microphone'}
                            </span>
                            <ChevronDown className="size-2.5" />
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end" className="min-w-56">
                            <DropdownMenuGroup>
                                <DropdownMenuLabel>
                                    Microphone
                                </DropdownMenuLabel>
                                <DropdownMenuSeparator />
                                <DropdownMenuRadioGroup
                                    value={voice.selectedDeviceId}
                                    onValueChange={voice.handleDeviceChange}
                                >
                                    {voice.devices.map((device) => (
                                        <DropdownMenuRadioItem
                                            key={device.deviceId}
                                            value={device.deviceId}
                                        >
                                            {device.label ||
                                                `Microphone ${device.deviceId.slice(0, 8)}`}
                                        </DropdownMenuRadioItem>
                                    ))}
                                </DropdownMenuRadioGroup>
                            </DropdownMenuGroup>
                        </DropdownMenuContent>
                    </DropdownMenu>
                </div>
            )}

            <CardContent>
                {loading ? (
                    <p className="py-8 text-center text-sm text-muted-foreground">
                        Loading...
                    </p>
                ) : expenses.length === 0 ? (
                    <p className="py-8 text-center text-sm text-muted-foreground">
                        No expenses yet. Add one or use the voice assistant.
                    </p>
                ) : (
                    <div className="flex flex-col gap-2">
                        {expenses.map((expense) => (
                            <div
                                key={expense._id}
                                className="flex items-center gap-3 rounded-lg border p-3"
                            >
                                <div className="flex-1">
                                    <div className="flex items-center gap-2">
                                        <span className="text-sm font-medium">
                                            {expense.description}
                                        </span>
                                        <Badge
                                            className={`text-xs capitalize ${CATEGORY_COLORS[expense.category] ?? CATEGORY_COLORS.other}`}
                                        >
                                            {expense.category}
                                        </Badge>
                                    </div>
                                    <span className="text-xs text-muted-foreground">
                                        {expense.date}
                                    </span>
                                </div>
                                <span className="text-sm font-semibold tabular-nums">
                                    {expense.currency === 'ARS' ? 'ARS' : 'USD'}{' '}
                                    ${(expense.amount / 100).toFixed(2)}
                                </span>
                                <Button
                                    variant="ghost"
                                    size="icon-xs"
                                    onClick={() => handleDelete(expense._id)}
                                >
                                    <Trash2 />
                                </Button>
                            </div>
                        ))}
                    </div>
                )}
            </CardContent>
        </Card>
    )
}
