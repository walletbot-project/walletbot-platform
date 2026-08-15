import type { CSSProperties } from 'react'
import { cn } from '@/lib/utils'

type IconProps = {
    /**
     * Material Symbols ligature name, e.g. `home` or `account_balance`. These
     * are the same glyph names the native app's `Icons.*` constants map to.
     */
    name: string
    /**
     * Filled glyph. Mirrors Flutter's `Icons.foo_rounded` (filled) vs
     * `Icons.foo_outlined` (not filled).
     */
    filled?: boolean
    /** Optical size in pixels. Material's default is 24. */
    size?: number
    /** Weight axis (100-700). Material's default is 400. */
    weight?: number
    className?: string
    style?: CSSProperties
}

/**
 * A single Material Symbols Rounded glyph, self-hosted so it renders the same
 * shapes the native app draws with Flutter's bundled Material icon font.
 *
 * Purely decorative by default: label the interactive element that contains
 * it (`aria-label` on the button) rather than the glyph itself.
 */
export function Icon({
    name,
    filled = false,
    size,
    weight,
    className,
    style,
}: IconProps) {
    return (
        <span
            aria-hidden
            className={cn('material-symbol shrink-0', className)}
            style={{
                '--md-icon-fill': filled ? 1 : 0,
                '--md-icon-size': size === undefined ? undefined : `${size}px`,
                '--md-icon-weight': weight,
                ...style,
            }}
        >
            {name}
        </span>
    )
}
