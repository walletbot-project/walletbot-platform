import { Check } from 'lucide-react'
import { cn } from '@/lib/utils'

type ColorSwatchesProps = {
    value: string
    onChange: (color: string) => void
    options: readonly string[]
}

/** Inline grid of selectable color swatches, mirroring the native ColorPicker. */
export function ColorSwatches({
    value,
    onChange,
    options,
}: ColorSwatchesProps) {
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
                        style={{ backgroundColor: option }}
                        aria-label={`Color ${option}`}
                        aria-pressed={isSelected}
                    >
                        {isSelected ? (
                            <Check className="size-4 text-white drop-shadow-sm" />
                        ) : null}
                    </button>
                )
            })}
        </div>
    )
}
