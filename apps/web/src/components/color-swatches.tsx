import { Icon } from '@/components/m3/icon'
import { foregroundOn, readableAccent } from '@/lib/entity-colors'
import { useT } from '@/lib/i18n'
import { useTheme } from '@/lib/theme'
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
     * Defaults to `readableAccent`, how entity accents (accounts, categories,
     * tags) are painted in the current theme.
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
    const { brightness } = useTheme()
    const selectedColor = value.toUpperCase()
    return (
        <div className="flex flex-wrap gap-2">
            {options.map((option) => {
                const isSelected = option.toUpperCase() === selectedColor
                const fill = previewColor
                    ? previewColor(option)
                    : readableAccent(option, brightness)
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
                        style={{ backgroundColor: fill }}
                        aria-label={t.common.colorSwatch({ color: option })}
                        aria-pressed={isSelected}
                    >
                        {isSelected ? (
                            <Icon
                                name="check"
                                size={16}
                                // A widget background preview is adapted so the
                                // theme's own on-surface reads against it. An
                                // entity accent is saturated enough in light
                                // that white reads best; in dark it is softened
                                // and lightened, so the check contrasts with it.
                                className={
                                    previewColor
                                        ? 'text-on-surface'
                                        : brightness === 'dark'
                                          ? undefined
                                          : 'text-white drop-shadow-sm'
                                }
                                style={
                                    !previewColor && brightness === 'dark'
                                        ? { color: foregroundOn(fill) }
                                        : undefined
                                }
                            />
                        ) : null}
                    </button>
                )
            })}
        </div>
    )
}
