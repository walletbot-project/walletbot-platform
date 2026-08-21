import { Icon } from '@/components/m3/icon'
import { useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'

type ColorSwatchesProps = {
    value: string
    onChange: (color: string) => void
    options: readonly string[]
    /**
     * Maps a stored option to the color actually painted. Pickers whose colors
     * render differently from how they are stored pass this so the swatch shows
     * the real thing: a dashboard widget background is adapted per theme (see
     * `readableWidgetBackground`), which is exactly what native's
     * `_ColorSwatches` previews. Selection still compares the stored option.
     */
    previewColor?: (option: string) => string
}

/** Inline grid of selectable color swatches, mirroring the native ColorPicker. */
export function ColorSwatches({
    value,
    onChange,
    options,
    previewColor,
}: ColorSwatchesProps) {
    const t = useT()
    const selectedColor = value.toUpperCase()
    return (
        <div className="flex flex-wrap gap-2">
            {options.map((option) => {
                const isSelected = option.toUpperCase() === selectedColor
                return (
                    <button
                        type="button"
                        key={option}
                        onClick={() => onChange(option)}
                        className={cn(
                            'flex size-9 items-center justify-center rounded-full border-2 transition-transform',
                            isSelected
                                ? 'border-foreground'
                                : 'border-transparent hover:scale-105',
                        )}
                        style={{
                            backgroundColor: previewColor
                                ? previewColor(option)
                                : option,
                        }}
                        aria-label={t.common.colorSwatch({ color: option })}
                        aria-pressed={isSelected}
                    >
                        {isSelected ? (
                            <Icon
                                name="check"
                                size={16}
                                // A previewed fill is theme-adapted, so the
                                // theme's own on-surface is what reads against
                                // it; a raw entity accent is saturated enough
                                // that white reads best.
                                className={
                                    previewColor
                                        ? 'text-on-surface'
                                        : 'text-white drop-shadow-sm'
                                }
                            />
                        ) : null}
                    </button>
                )
            })}
        </div>
    )
}
