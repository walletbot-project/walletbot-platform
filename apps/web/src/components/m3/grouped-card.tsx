import type { CSSProperties, ReactNode } from 'react'
import { cn } from '@/lib/utils'

type GroupedCardProps = {
    /** Shape for this card's position in the group — see `groupedRadius`. */
    radius: CSSProperties
    children: ReactNode
    onClick?: () => void
    className?: string
    /** Accessible name when the card is interactive but visually terse. */
    'aria-label'?: string
}

/**
 * A single card within an M3 expressive grouped list: card surface, injected
 * corner shape, optional press affordance. Mirrors the native `GroupedCard`
 * widget; the shape tokens live in `@/lib/grouped-list`.
 */
export function GroupedCard({
    radius,
    children,
    onClick,
    className,
    'aria-label': ariaLabel,
}: GroupedCardProps) {
    const shared = cn(
        'block w-full overflow-hidden bg-surface-container-high text-left text-on-surface',
        className,
    )

    if (!onClick) {
        return (
            <div className={shared} style={radius}>
                {children}
            </div>
        )
    }

    return (
        <button
            type="button"
            aria-label={ariaLabel}
            onClick={onClick}
            style={radius}
            className={cn(
                shared,
                'm3-state-layer cursor-pointer focus-visible:outline-none',
            )}
        >
            {children}
        </button>
    )
}
