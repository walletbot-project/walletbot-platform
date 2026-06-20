import { CATEGORY_FALLBACK_ICON, CATEGORY_ICON_MAP } from '@/lib/category-icons'

/** Renders a category's glyph by its stored name, falling back to the default. */
export function CategoryIcon({
    name,
    className,
    color,
}: {
    name?: string
    className?: string
    color?: string
}) {
    const Glyph =
        (name ? CATEGORY_ICON_MAP[name] : undefined) ?? CATEGORY_FALLBACK_ICON
    return <Glyph className={className} style={color ? { color } : undefined} />
}
