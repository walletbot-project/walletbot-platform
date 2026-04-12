import { Check } from 'lucide-react'
import { cn } from '@/lib/utils'

const PRESET_COLORS = [
    '#ef4444',
    '#f97316',
    '#f59e0b',
    '#eab308',
    '#84cc16',
    '#22c55e',
    '#14b8a6',
    '#06b6d4',
    '#3b82f6',
    '#6366f1',
    '#8b5cf6',
    '#a855f7',
    '#d946ef',
    '#ec4899',
    '#f43f5e',
    '#6b7280',
]

interface ColorPickerProps {
    value: string
    onChange: (color: string) => void
}

export function ColorPicker({ value, onChange }: ColorPickerProps) {
    return (
        <div className="flex flex-wrap gap-1.5">
            {PRESET_COLORS.map((color) => (
                <button
                    key={color}
                    type="button"
                    className={cn(
                        'flex size-7 items-center justify-center rounded-full border-2 transition-transform hover:scale-110',
                        value === color
                            ? 'border-foreground'
                            : 'border-transparent',
                    )}
                    style={{ backgroundColor: color }}
                    onClick={() => onChange(color)}
                >
                    {value === color && (
                        <Check className="size-3.5 text-white" />
                    )}
                </button>
            ))}
        </div>
    )
}
