import { useState } from 'react'
import {
    Popover,
    PopoverContent,
    PopoverTrigger,
} from '@/components/ui/popover'
import type { IconOption } from '@/lib/account-icons'
import { cn } from '@/lib/utils'

type IconPickerProps = {
    icon: string
    color: string
    onIconChange: (name: string) => void
    icons: readonly IconOption[]
}

/**
 * The tinted, tappable icon tile that opens an icon-grid popover. Used both
 * standalone (as the editable identity glyph in detail sheets) and composed
 * with ColorSwatches inside IconColorPicker for the create dialogs.
 */
export function IconPicker({
    icon,
    color,
    onIconChange,
    icons,
}: IconPickerProps) {
    const [open, setOpen] = useState(false)
    const ActiveIcon = icons.find((i) => i.name === icon)?.Icon ?? icons[0].Icon

    return (
        <Popover open={open} onOpenChange={setOpen}>
            <PopoverTrigger
                render={
                    <button
                        type="button"
                        className="flex size-14 shrink-0 items-center justify-center rounded-2xl"
                        style={{ backgroundColor: `${color}47` }}
                        aria-label="Elegir ícono"
                    />
                }
            >
                <ActiveIcon className="size-7" style={{ color }} />
            </PopoverTrigger>
            <PopoverContent className="w-64">
                <div className="grid grid-cols-5 gap-1.5">
                    {icons.map(({ name, Icon }) => {
                        const isSelected = name === icon
                        return (
                            <button
                                type="button"
                                key={name}
                                onClick={() => {
                                    onIconChange(name)
                                    setOpen(false)
                                }}
                                className={cn(
                                    'flex size-10 items-center justify-center rounded-xl border-2 transition-colors',
                                    isSelected
                                        ? 'border-foreground'
                                        : 'border-transparent hover:bg-accent',
                                )}
                                style={
                                    isSelected
                                        ? { backgroundColor: `${color}28` }
                                        : undefined
                                }
                                aria-label={name}
                                aria-pressed={isSelected}
                            >
                                <Icon className="size-5" style={{ color }} />
                            </button>
                        )
                    })}
                </div>
            </PopoverContent>
        </Popover>
    )
}
