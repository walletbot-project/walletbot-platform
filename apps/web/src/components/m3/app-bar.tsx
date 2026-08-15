import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'

type AppBarProps = {
    title: ReactNode
    /** Leading slot — a back/close button, matching Flutter's `AppBar.leading`. */
    leading?: ReactNode
    /** Trailing actions, matching Flutter's `AppBar.actions`. */
    actions?: ReactNode
    /** Rendered flush under the bar — the tab bar slot (`AppBar.bottom`). */
    bottom?: ReactNode
    className?: string
}

/**
 * The small top app bar, laid out like Flutter's `AppBar`: 64dp tall, a
 * `titleLarge` title inset 16dp from the leading edge, and 48dp action slots.
 */
export function AppBar({
    title,
    leading,
    actions,
    bottom,
    className,
}: AppBarProps) {
    return (
        <header
            className={cn(
                'sticky top-0 z-20 shrink-0 bg-surface text-on-surface',
                className,
            )}
        >
            <div className="flex h-16 items-center gap-1 pr-1 pl-4">
                {leading ? (
                    <div className="-ml-2 flex items-center">{leading}</div>
                ) : null}
                <h1 className="m3-title-large min-w-0 flex-1 truncate">
                    {title}
                </h1>
                {actions ? (
                    <div className="flex items-center gap-1">{actions}</div>
                ) : null}
            </div>
            {bottom}
        </header>
    )
}
