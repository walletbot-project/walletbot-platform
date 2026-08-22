import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'
import { Icon } from './icon'

type StateMessageProps = {
    /** Material Symbols ligature name for the 64px hero glyph. */
    icon: string
    title: string
    detail?: ReactNode
    /** Rendered under the copy — typically a single call-to-action button. */
    action?: ReactNode
    /** Errors tint the glyph with the error color, as the native screens do. */
    tone?: 'neutral' | 'error'
}

/**
 * The centred empty/error state shared by the list screens, matching the
 * `_EmptyBody` / `_ErrorBody` / `_CategoriesMessage` blocks in the native app:
 * a 64px outlined glyph, a `titleMedium` headline and a `bodyMedium` detail.
 */
export function StateMessage({
    icon,
    title,
    detail,
    action,
    tone = 'neutral',
}: StateMessageProps) {
    return (
        <div className="flex flex-1 flex-col items-center justify-center p-8 text-center">
            <Icon
                name={icon}
                size={64}
                className={cn(tone === 'error' ? 'text-error' : 'text-outline')}
            />
            <h2 className="m3-title-medium mt-4 text-on-surface">{title}</h2>
            {detail ? (
                <p className="m3-body-medium mt-2 text-on-surface-variant">
                    {detail}
                </p>
            ) : null}
            {action ? <div className="mt-6">{action}</div> : null}
        </div>
    )
}
