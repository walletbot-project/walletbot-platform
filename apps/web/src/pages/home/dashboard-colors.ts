import {
    type BackgroundStyle,
    DEFAULT_VALUE_BACKGROUND,
} from '@wallet-bot/shared'
import { clamp, type Hsl, hexToHsl, hslToCss } from '@/lib/color-hsl'
import { COLOR_OPTIONS } from '@/lib/entity-colors'
import type { Brightness } from '@/lib/theme'

/**
 * Adapts a stored color so its content stays legible in both themes: the
 * native `pastelize` (keep the hue, drop saturation, lift lightness) in
 * light, a deep tint of the same hue in dark. Ported from
 * `readableWidgetBackground`.
 */
export function readableWidgetBackground(
    hex: string,
    brightness: Brightness,
): string {
    const hsl = hexToHsl(hex)
    if (!hsl) return hex
    const pastel: Hsl = {
        h: hsl.h,
        s: clamp(hsl.s * 0.6, 0, 1),
        l: clamp(hsl.l + (1 - hsl.l) * 0.7, 0, 1),
    }
    if (brightness === 'light') return hslToCss(pastel)
    return hslToCss({
        h: pastel.h,
        s: clamp(pastel.s, 0.3, 0.6),
        l: 0.24,
    })
}

/**
 * Resolves a widget's configured background to a CSS color, or null to keep
 * the default `surfaceContainer`. `numericValue` is in *displayed* units:
 * amount units for money widgets, row count for lists, slice total for charts.
 */
export function resolveBackground(
    style: BackgroundStyle,
    numericValue: number | null,
    brightness: Brightness,
): string | null {
    switch (style.mode) {
        case 'none':
            return null
        case 'fixed': {
            const hex = style.fixedColor ?? COLOR_OPTIONS[0] ?? '#69F0AE'
            return readableWidgetBackground(hex, brightness)
        }
        case 'value': {
            if (numericValue === null) return null
            const value = style.value ?? DEFAULT_VALUE_BACKGROUND
            const lower = Math.min(value.low, value.high)
            const upper = Math.max(value.low, value.high)
            const hex =
                numericValue < lower
                    ? value.lowColor
                    : numericValue > upper
                      ? value.highColor
                      : value.betweenColor
            return readableWidgetBackground(hex, brightness)
        }
    }
}
