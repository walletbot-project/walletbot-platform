import type { ReactNode } from 'react'
import { foregroundOn } from '@/lib/entity-colors'
import { useTheme } from '@/lib/theme'
import { cn } from '@/lib/utils'

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
