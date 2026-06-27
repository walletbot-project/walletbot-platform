import { ColorSwatches } from '@/components/color-swatches'
import { IconPicker } from '@/components/icon-picker'
import type { IconOption } from '@/lib/account-icons'

type IconColorPickerProps = {
    icon: string
    color: string
    onIconChange: (name: string) => void
    onColorChange: (color: string) => void
    icons: readonly IconOption[]
    colors: readonly string[]
}

/**
 * The tinted, tappable icon tile (opens an icon grid popover) paired with an
 * inline color swatch row. Mirrors the native create-account / create-category
 * "ícono y color" control.
 */
export function IconColorPicker({
    icon,
    color,
    onIconChange,
    onColorChange,
    icons,
    colors,
}: IconColorPickerProps) {
    return (
        <div className="flex items-start gap-4">
            <IconPicker
                icon={icon}
                color={color}
                onIconChange={onIconChange}
                icons={icons}
            />
            <div className="flex-1">
                <ColorSwatches
                    value={color}
                    onChange={onColorChange}
                    options={colors}
                />
            </div>
        </div>
    )
}
