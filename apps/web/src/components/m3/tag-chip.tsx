import type { ReactNode } from 'react'
import { useTheme } from '@/lib/theme'
import { cn } from '@/lib/utils'

/**
 * Whether black or white reads better on `color` — the web counterpart of the
 * native `foregroundOn` helper.
 */
function foregroundOn(color: string): string {
    const hex = color.replace('#', '')
    if (hex.length !== 6) return '#000000'
    const r = Number.parseInt(hex.slice(0, 2), 16)
    const g = Number.parseInt(hex.slice(2, 4), 16)
    const b = Number.parseInt(hex.slice(4, 6), 16)
    // Relative luminance, matching Flutter's `Color.computeLuminance` weights.
    const luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    return luminance > 0.5 ? '#000000' : '#ffffff'
}

/**
 * A tag rendered as a Material 3 chip, matching the native `tagChipStyle`
 * helper: the fill is always the tag's own identity color, while the avatar
 * dot and label adapt per theme so they stay legible on any fill.
 */
export function TagChip({
    name,
    color,
    trailing,
    onClick,
    className,
}: {
    name: string
    color: string
    trailing?: ReactNode
    onClick?: () => void
    className?: string
}) {
    const { brightness } = useTheme()
    const isDark = brightness === 'dark'
    const contrast = foregroundOn(color)

    const content = (
        <>
            <span
                aria-hidden
                className="size-4.5 shrink-0 rounded-full"
                style={{ backgroundColor: isDark ? contrast : '#ffffff' }}
            />
            {name}
            {trailing}
        </>
    )

    const shared = cn(
        'm3-label-large inline-flex h-8 items-center gap-2 rounded-lg pr-4 pl-1.5',
        className,
    )
    const style = {
        backgroundColor: color,
        color: isDark ? contrast : 'var(--md-sys-color-on-surface-variant)',
    }

    if (!onClick) {
        return (
            <span className={shared} style={style}>
                {content}
            </span>
        )
    }

    return (
        <button
            type="button"
            onClick={onClick}
            className={cn(shared, 'm3-state-layer cursor-pointer')}
            style={style}
        >
            {content}
        </button>
    )
}
