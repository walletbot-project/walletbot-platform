import { Icon } from '@/components/m3/icon'
import { accountIcon } from '@/lib/account-icons'

/** Renders an account's glyph by its stored name, falling back to the default. */
export function AccountIcon({
    name,
    size,
    color,
    className,
}: {
    name?: string
    size?: number
    color?: string
    className?: string
}) {
    const option = accountIcon(name)
    return (
        <Icon
            name={option.symbol}
            filled={option.filled}
            size={size}
            className={className}
            style={color ? { color } : undefined}
        />
    )
}
