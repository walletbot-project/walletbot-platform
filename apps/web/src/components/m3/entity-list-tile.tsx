import type { CSSProperties, ReactNode } from 'react'
import { useReadableAccent } from '@/lib/entity-colors'
import { cn } from '@/lib/utils'
import { GroupedCard } from './grouped-card'
import { Icon } from './icon'

type EntityListTileProps = {
    /** Shape for this tile's position in the group — see `groupedRadius`. */
    radius: CSSProperties
    /** Leading avatar. Usually an `EntityAvatar`. */
    leading: ReactNode
    title: string
    subtitle?: ReactNode
    /**
     * Trailing content — a balance, a count, or nothing. A chevron is appended
     * after it when `chevron` is set, matching the native category/tag tiles.
     */
    trailing?: ReactNode
    chevron?: boolean
    onClick?: () => void
}

/**
 * One row in an M3 expressive grouped list: accent icon avatar, title, an
 * optional subtitle, and a trailing slot. Mirrors the shared
 * `AccountListTile` / `CategoryListTile` widgets in the native app.
 */
export function EntityListTile({
    radius,
    leading,
    title,
    subtitle,
    trailing,
    chevron = false,
    onClick,
}: EntityListTileProps) {
    return (
        <GroupedCard radius={radius} onClick={onClick}>
            <div className="flex items-center gap-4 px-4 py-4">
                {leading}
                <div className="flex min-w-0 flex-1 flex-col">
                    <span className="m3-body-large truncate">{title}</span>
                    {subtitle ? (
                        <span className="m3-body-small truncate text-on-surface-variant">
                            {subtitle}
                        </span>
                    ) : null}
                </div>
                {trailing ? (
                    <div className="shrink-0 pl-3">{trailing}</div>
                ) : null}
                {chevron ? (
                    <Icon
                        name="chevron_right"
                        filled
                        className="text-on-surface-variant"
                    />
                ) : null}
            </div>
        </GroupedCard>
    )
}

/**
 * The tinted circular avatar the entity tiles lead with: the entity's accent
 * color at 18% behind its icon, matching the native tiles.
 */
export function EntityAvatar({
    color,
    children,
    size = 40,
    className,
}: {
    color: string
    children: ReactNode
    size?: number
    className?: string
}) {
    const paint = useReadableAccent()
    return (
        <span
            className={cn(
                'flex shrink-0 items-center justify-center rounded-full',
                className,
            )}
            style={{
                backgroundColor: `${paint(color)}2E`,
                width: size,
                height: size,
            }}
        >
            {children}
        </span>
    )
}
