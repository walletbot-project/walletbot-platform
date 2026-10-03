// HSL conversions for stored hex colors, used by the widget background adapter
// in pages/home/dashboard-colors.ts. Mirrors Flutter's `HSLColor`, which the
// native adapter uses.

export type Hsl = { h: number; s: number; l: number }

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

/** Parses a `#RRGGBB` / `#RRGGBBAA` color into HSL (alpha is dropped). */
export function hexToHsl(hex: string): Hsl | null {
    const rgb = hexToRgb(hex)
    return rgb ? rgbToHsl(rgb.r, rgb.g, rgb.b) : null
}

/** Formats an HSL color as a CSS `hsl()` string. */
export function hslToCss({ h, s, l }: Hsl): string {
    return `hsl(${(h * 360).toFixed(2)} ${(s * 100).toFixed(2)}% ${(l * 100).toFixed(2)}%)`
}

export const clamp = (value: number, min: number, max: number) =>
    Math.min(Math.max(value, min), max)
