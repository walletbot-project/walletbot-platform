import type { IconOption } from './account-icons'

/**
 * Icon catalog for categories. Names *and* glyphs mirror the native catalog
 * (apps/native/lib/components/category_icons.dart), so a category looks the
 * same on both platforms.
 */
export const CATEGORY_ICONS: readonly IconOption[] = [
    { name: 'category', symbol: 'category', filled: true },
    { name: 'receipt', symbol: 'receipt_long', filled: true },
    { name: 'shopping_bag', symbol: 'shopping_bag', filled: true },
    { name: 'shopping_cart', symbol: 'shopping_cart', filled: true },
    { name: 'savings', symbol: 'savings', filled: true },
    { name: 'health', symbol: 'favorite', filled: true },
    { name: 'education', symbol: 'school', filled: true },
    { name: 'restaurant', symbol: 'restaurant', filled: true },
    { name: 'transport', symbol: 'directions_bus', filled: true },
    { name: 'home', symbol: 'home', filled: true },
    { name: 'celebration', symbol: 'celebration', filled: true },
    { name: 'fitness', symbol: 'fitness_center', filled: true },
    { name: 'pets', symbol: 'pets', filled: true },
    { name: 'help', symbol: 'help', filled: false },
]

export const CATEGORY_DEFAULT_ICON = 'category'

export const CATEGORY_FALLBACK_ICON: IconOption = CATEGORY_ICONS[0]

const CATEGORY_ICON_MAP: ReadonlyMap<string, IconOption> = new Map(
    CATEGORY_ICONS.map((option) => [option.name, option]),
)

/** Resolves a stored icon name to its glyph, falling back to the default. */
export function categoryIcon(name: string | undefined): IconOption {
    return (
        (name ? CATEGORY_ICON_MAP.get(name) : undefined) ??
        CATEGORY_FALLBACK_ICON
    )
}
