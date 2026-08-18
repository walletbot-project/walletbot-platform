import type { ReactNode } from 'react'
import { Icon } from '@/components/m3/icon'
import { useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'

type DashboardCellProps = {
    title: string
    icon?: string
    trailing?: ReactNode
    /** Resolved CSS color, or null to keep the default `surfaceContainer`. */
    backgroundColor: string | null
    minHeight?: number
    children: ReactNode
}

/**
 * Shared visual shell for dashboard widgets, ported from the native
 * `DashboardCell`: an 8dp surface-tinted card with a label-large title, an
 * optional trailing slot, and a small glyph floating in the bottom-left corner.
 */
export function DashboardCell({
    title,
    icon,
    trailing,
    backgroundColor,
    minHeight,
    children,
}: DashboardCellProps) {
    const t = useT()
    return (
        <div
            className={cn(
                'relative flex h-full flex-col rounded-lg p-4',
                backgroundColor === null ? 'bg-surface-container' : undefined,
            )}
            style={{
                minHeight,
                ...(backgroundColor === null
                    ? {}
                    : {
                          backgroundColor,
                          color: 'var(--md-sys-color-on-surface)',
                      }),
            }}
        >
            <div className="flex items-center gap-2">
                <h3 className="m3-label-large min-w-0 flex-1 truncate font-bold text-on-surface-variant">
                    {title || t.dashboard.widget}
                </h3>
                {trailing}
            </div>
            <div className="mt-3 min-w-0 flex-1">{children}</div>
            {icon ? (
                <span className="pointer-events-none absolute bottom-4 left-4 flex size-5 items-center justify-center rounded-md bg-primary-container/60 text-on-primary-container">
                    <Icon name={icon} size={13} />
                </span>
            ) : null}
        </div>
    )
}
