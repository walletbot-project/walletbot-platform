import {
    type BackgroundStyle,
    DEFAULT_VALUE_BACKGROUND,
} from '@wallet-bot/shared'
import { COLOR_OPTIONS } from '@/lib/entity-colors'
import type { Brightness } from '@/lib/theme'

type Hsl = { h: number; s: number; l: number }

function hexToRgb(hex: string): { r: number; g: number; b: number } | null {
    const clean = hex.replace('#', '')
    if (clean.length !== 6 && clean.length !== 8) return null
    const value = Number.parseInt(clean.slice(0, 6), 16)
    if (Number.isNaN(value)) return null
    return {
        r: (value >> 16) & 0xff,
        g: (value >> 8) & 0xff,
        b: value & 0xff,
    }
}

function rgbToHsl(r: number, g: number, b: number): Hsl {
    const rn = r / 255
    const gn = g / 255
    const bn = b / 255
    const max = Math.max(rn, gn, bn)
    const min = Math.min(rn, gn, bn)
    const l = (max + min) / 2
    if (max === min) return { h: 0, s: 0, l }
    const d = max - min
    const s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    let h: number
    if (max === rn) h = ((gn - bn) / d + (gn < bn ? 6 : 0)) / 6
    else if (max === gn) h = ((bn - rn) / d + 2) / 6
    else h = ((rn - gn) / d + 4) / 6
    return { h, s, l }
}

function hslToCss({ h, s, l }: Hsl): string {
    return `hsl(${(h * 360).toFixed(2)} ${(s * 100).toFixed(2)}% ${(l * 100).toFixed(2)}%)`
}

function toHsl(hex: string): Hsl | null {
    const rgb = hexToRgb(hex)
    return rgb ? rgbToHsl(rgb.r, rgb.g, rgb.b) : null
}

const clamp = (value: number, min: number, max: number) =>
    Math.min(Math.max(value, min), max)

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
    const hsl = toHsl(hex)
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
