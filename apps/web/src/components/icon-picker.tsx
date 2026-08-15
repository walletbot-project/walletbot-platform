import { useState } from 'react'
import { M3Dialog } from '@/components/m3/dialog'
import { Icon } from '@/components/m3/icon'
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
 * The tinted, tappable icon tile that opens the icon grid. The grid is a
 * dialog, matching the native `showIconPickerDialog`
 * (apps/native/lib/components/icon_picker.dart) — a popover would anchor to
 * the tile and read as a menu instead.
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
        <>
            <button
                type="button"
                onClick={() => setOpen(true)}
                className="m3-state-layer flex size-14 shrink-0 cursor-pointer items-center justify-center rounded-2xl"
                style={{ backgroundColor: `${color}47` }}
                aria-label={t.common.chooseIcon}
            >
                <Icon
                    name={active.symbol}
                    filled={active.filled}
                    size={28}
                    style={{ color }}
                />
            </button>

            <M3Dialog
                open={open}
                onOpenChange={setOpen}
                title={t.common.chooseIcon}
            >
                <div className="flex flex-wrap gap-3">
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
                                    'flex size-13 cursor-pointer items-center justify-center rounded-2xl border-2 transition-colors',
                                    isSelected
                                        ? 'border-transparent'
                                        : 'border-transparent bg-surface-container-highest',
                                )}
                                style={
                                    isSelected
                                        ? {
                                              backgroundColor: `${color}47`,
                                              borderColor: color,
                                          }
                                        : undefined
                                }
                                aria-label={name}
                                aria-pressed={isSelected}
                            >
                                <Icon
                                    name={symbol}
                                    filled={filled}
                                    size={26}
                                    style={{
                                        color: isSelected
                                            ? color
                                            : 'var(--md-sys-color-on-surface-variant)',
                                    }}
                                />
                            </button>
                        )
                    })}
                </div>
            </M3Dialog>
        </>
    )
}
