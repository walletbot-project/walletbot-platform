import { useState } from 'react'
import { Icon } from '@/components/m3/icon'
import {
    Popover,
    PopoverContent,
    PopoverTrigger,
} from '@/components/ui/popover'
import type { IconOption } from '@/lib/account-icons'
import { useT } from '@/lib/i18n'
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
    const t = useT()
    const [open, setOpen] = useState(false)
    const active = icons.find((option) => option.name === icon) ?? icons[0]

    return (
        <Popover open={open} onOpenChange={setOpen}>
            <PopoverTrigger
                render={
                    <button
                        type="button"
                        className="flex size-14 shrink-0 items-center justify-center rounded-2xl"
                        style={{ backgroundColor: `${color}47` }}
                        aria-label={t.common.chooseIcon}
                    />
                }
            >
                <Icon
                    name={active.symbol}
                    filled={active.filled}
                    size={28}
                    style={{ color }}
                />
            </PopoverTrigger>
            <PopoverContent className="w-64">
                <div className="grid grid-cols-5 gap-1.5">
                    {icons.map(({ name, symbol, filled }) => {
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
                                <Icon
                                    name={symbol}
                                    filled={filled}
                                    size={20}
                                    style={{ color }}
                                />
                            </button>
                        )
                    })}
                </div>
            </PopoverContent>
        </Popover>
    )
}
