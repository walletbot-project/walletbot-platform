import { IconButton } from 'actify'
import type { ReactNode } from 'react'
import { useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'
import { Icon } from './icon'

type AppBarProps = {
    /**
     * Omitted for bars that carry only actions — a detail pane's close bar, for
     * instance, where the content below is already headed.
     */
    title?: ReactNode
    /** Leading slot — a back/close button, matching Flutter's `AppBar.leading`. */
    leading?: ReactNode
    /** Trailing actions, matching Flutter's `AppBar.actions`. */
    actions?: ReactNode
    className?: string
}

/**
 * The small top app bar, laid out like Flutter's `AppBar`: 64dp tall, a
 * `titleLarge` title inset 16dp from the leading edge, and 48dp action slots.
 */
export function AppBar({ title, leading, actions, className }: AppBarProps) {
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
                {title === undefined ? (
                    <span className="min-w-0 flex-1" />
                ) : (
                    <h1 className="m3-title-large min-w-0 flex-1 truncate">
                        {title}
                    </h1>
                )}
                {actions ? (
                    <div className="flex items-center gap-1">{actions}</div>
                ) : null}
            </div>
        </header>
    )
}

/**
 * The bar-with-a-close-action every non-sheet occupant leads with — one
 * definition so the affordance can't drift between forms and detail panes.
 */
export function CloseAppBar({
    title,
    onClose,
}: {
    title?: ReactNode
    onClose: () => void
}) {
    const t = useT()
    return (
        <AppBar
            title={title}
            leading={
                <IconButton
                    aria-label={t.common.close}
                    onPress={onClose}
                    className="text-on-surface-variant"
                >
                    <Icon name="close" />
                </IconButton>
            }
        />
    )
}
