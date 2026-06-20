// Single accent palette shared by every entity picker (accounts, categories,
// tags). Mirrors the native `colorOptions` in
// apps/native/lib/components/color_utils.dart so colors stay identical across
// platforms.
export const COLOR_OPTIONS = [
    '#69F0AE',
    '#26A69A',
    '#42A5F5',
    '#FFCA28',
    '#FF7043',
    '#AB47BC',
    '#78909C',
    '#3B82F6',
    '#14B8A6',
    '#F59E0B',
    '#EF4444',
    '#6366F1',
    '#8B5CF6',
    '#10B981',
    '#EC4899',
] as const

export const ACCOUNT_DEFAULT_COLOR = '#3B82F6'
export const CATEGORY_DEFAULT_COLOR = '#6366F1'
export const TAG_DEFAULT_COLOR = '#69F0AE'

/** Returns the stored color upper-cased, or the fallback when absent. */
export function normalizeColor(
    color: string | null | undefined,
    fallback: string,
): string {
    if (!color) return fallback
    return color.toUpperCase()
}

/** A translucent variant of a hex color for tinted backgrounds (e.g. `1F` ≈ 12%). */
export function tint(color: string, alphaHex: string): string {
    return `${color}${alphaHex}`
}
