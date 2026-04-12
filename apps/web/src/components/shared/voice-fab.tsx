import { ChevronDown, Mic, MicOff, Phone, PhoneOff } from 'lucide-react'
import { Button } from '@/components/ui/button'
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
import { useVoice } from '@/hooks/use-voice'

export function VoiceFab() {
    const voice = useVoice()

    if (voice.isConnected) {
        return (
            <div className="fixed bottom-20 right-4 z-50 flex flex-col items-end gap-2 md:bottom-6 md:right-6">
                <div className="flex items-center gap-1.5 rounded-xl border bg-background p-2 shadow-lg">
                    {/* Level meter */}
                    <div className="h-1.5 w-20 overflow-hidden rounded-full bg-muted">
                        <div
                            className="h-full rounded-full bg-green-500 transition-[width] duration-75"
                            style={{
                                width: `${voice.micLevel * 100}%`,
                            }}
                        />
                    </div>

                    {/* Mic picker */}
                    <DropdownMenu>
                        <DropdownMenuTrigger className="inline-flex h-6 items-center gap-1 rounded-md px-1.5 text-xs text-muted-foreground hover:bg-accent hover:text-accent-foreground">
                            <Mic className="size-3" />
                            <span className="max-w-20 truncate">
                                {voice.devices.find(
                                    (d) =>
                                        d.deviceId === voice.selectedDeviceId,
                                )?.label || 'Mic'}
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
                                                `Mic ${device.deviceId.slice(0, 8)}`}
                                        </DropdownMenuRadioItem>
                                    ))}
                                </DropdownMenuRadioGroup>
                            </DropdownMenuGroup>
                        </DropdownMenuContent>
                    </DropdownMenu>

                    {/* Mute */}
                    <Button
                        variant={voice.isMuted ? 'secondary' : 'outline'}
                        size="icon-xs"
                        onClick={() => voice.setIsMuted((m) => !m)}
                    >
                        {voice.isMuted ? (
                            <MicOff className="size-3.5" />
                        ) : (
                            <Mic className="size-3.5" />
                        )}
                    </Button>

                    {/* Disconnect */}
                    <Button
                        variant="destructive"
                        size="sm"
                        onClick={voice.disconnect}
                    >
                        <PhoneOff className="size-3.5" />
                        End
                    </Button>
                </div>
            </div>
        )
    }

    return (
        <div className="fixed bottom-20 right-4 z-50 md:bottom-6 md:right-6">
            <Button
                size="lg"
                className="size-12 rounded-full shadow-lg"
                onClick={voice.connect}
                disabled={voice.isConnecting}
            >
                <Phone className="size-5" />
            </Button>
        </div>
    )
}
