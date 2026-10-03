// OKLab conversions for stored hex colors, used by `readableAccent` in
// entity-colors.ts. Mirrors the private helpers next to the native
// `readableAccent` (apps/native/lib/components/color_utils.dart) step for
// step, so both platforms paint the same hex for the same stored color.

export type Oklab = { l: number; a: number; b: number }

/** Linear sRGB channels; they may fall outside 0–1 when out of gamut. */
export type LinearRgb = { r: number; g: number; b: number }

const decodeSrgb = (c: number) =>
    c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4

const encodeSrgb = (c: number) =>
    c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055

/** Parses a `#RRGGBB` / `#RRGGBBAA` color into OKLab (alpha is dropped). */
export function hexToOklab(hex: string): Oklab | null {
    const clean = hex.replace('#', '')
    if (clean.length !== 6 && clean.length !== 8) return null
    const value = Number.parseInt(clean.slice(0, 6), 16)
    if (Number.isNaN(value)) return null
    const r = decodeSrgb(((value >> 16) & 0xff) / 255)
    const g = decodeSrgb(((value >> 8) & 0xff) / 255)
    const b = decodeSrgb((value & 0xff) / 255)
    const l =
        (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    const m =
        (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    const s =
        (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return {
        l: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
        a: 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
        b: 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
    }
}

/** OKLab back to linear sRGB, without clamping. */
export function oklabToLinearRgb({ l: lightness, a, b }: Oklab): LinearRgb {
    const l = (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3
    const m = (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3
    const s = (lightness - 0.0894841775 * a - 1.291485548 * b) ** 3
    return {
        r: 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        g: -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        b: -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
    }
}

/** Whether every channel fits in sRGB (with a small rounding tolerance). */
export function inSrgbGamut({ r, g, b }: LinearRgb): boolean {
    const tolerance = 1e-4
    const fits = (c: number) => c >= -tolerance && c <= 1 + tolerance
    return fits(r) && fits(g) && fits(b)
}

/** Clamps and gamma-encodes linear sRGB into upper-case `#RRGGBB`. */
export function linearRgbToHex({ r, g, b }: LinearRgb): string {
    const channel = (c: number) =>
        Math.round(encodeSrgb(Math.min(Math.max(c, 0), 1)) * 255)
            .toString(16)
            .padStart(2, '0')
    return `#${channel(r)}${channel(g)}${channel(b)}`.toUpperCase()
}
