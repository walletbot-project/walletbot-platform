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
 * Adapts a stored entity accent (account, category, tag) to how it is painted
 * in the current theme — the web port of the native `readableAccent`
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
 * Whether black or white reads better on `color` — the web counterpart of the
 * native `foregroundOn` helper.
 */
export function foregroundOn(color: string): string {
    const hex = color.replace('#', '')
    if (hex.length !== 6) return '#000000'
    const r = Number.parseInt(hex.slice(0, 2), 16)
    const g = Number.parseInt(hex.slice(2, 4), 16)
    const b = Number.parseInt(hex.slice(4, 6), 16)
    // Relative luminance, matching Flutter's `Color.computeLuminance` weights.
    const luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    return luminance > 0.5 ? '#000000' : '#ffffff'
}
