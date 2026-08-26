import { Icon } from '@/components/m3/icon'
import { categoryIcon } from '@/lib/category-icons'

/** Renders a category's glyph by its stored name, falling back to the default. */
export function CategoryIcon({
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
    const option = categoryIcon(name)
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
