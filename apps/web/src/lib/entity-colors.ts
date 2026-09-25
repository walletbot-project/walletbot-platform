import { clamp, hexToHsl, hslToHex } from '@/lib/color-hsl'
import { type Brightness, useTheme } from '@/lib/theme'

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
    '#06B6D4',
    '#84CC16',
    '#F43F5E',
    '#0EA5E9',
    '#D946EF',
    '#F97316',
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

/**
 * Adapts a stored account or category accent to how it is painted in the
 * current theme (tags are not adapted: they keep their raw color) — the web port of the native `readableAccent`
 * (apps/native/lib/components/color_utils.dart). Saturated accents suit light
 * surfaces but glare on dark ones, so light returns the stored color as-is and
 * dark rebuilds it as a softer, lighter tone of the same hue. Idempotent, and
 * always `#RRGGBB` so callers can keep appending hex alpha suffixes. Anything
 * that is not a hex color passes through unchanged. The stored value never
 * changes — only what gets painted.
 */
export function readableAccent(hex: string, brightness: Brightness): string {
    if (brightness === 'light') return hex
    const hsl = hexToHsl(hex)
    if (!hsl) return hex
    return hslToHex({ h: hsl.h, s: clamp(hsl.s, 0, 0.65), l: 0.72 })
}

/** [readableAccent] bound to the current theme. */
export function useReadableAccent(): (hex: string) => string {
    const { brightness } = useTheme()
    return (hex) => readableAccent(hex, brightness)
}

/**
 * Whether black or white reads better on `color` — a port of the native
 * `foregroundOn` helper (apps/native/lib/components/color_utils.dart): picks
 * whichever yields the higher WCAG contrast ratio.
 */
export function foregroundOn(color: string): string {
    const hex = color.replace('#', '')
    if (hex.length !== 6) return '#000000'
    // Relative luminance of linearized sRGB, as Flutter's
    // `Color.computeLuminance` computes it.
    const channel = (offset: number) => {
        const c = Number.parseInt(hex.slice(offset, offset + 2), 16) / 255
        return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
    }
    const luminance =
        0.2126 * channel(0) + 0.7152 * channel(2) + 0.0722 * channel(4)
    const contrastWithWhite = 1.05 / (luminance + 0.05)
    const contrastWithBlack = (luminance + 0.05) / 0.05
    return contrastWithWhite >= contrastWithBlack ? '#ffffff' : '#000000'
}
