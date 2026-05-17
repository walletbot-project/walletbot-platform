// Mirrors the native app's tag palette (Material Design accents).
export const TAG_DEFAULT_COLOR = '#69F0AE'

export const TAG_COLOR_OPTIONS = [
    TAG_DEFAULT_COLOR,
    '#26A69A',
    '#42A5F5',
    '#FFCA28',
    '#FF7043',
    '#AB47BC',
    '#78909C',
] as const

export function normalizeTagColor(color: string | null | undefined): string {
    if (!color) return TAG_DEFAULT_COLOR
    return color.toUpperCase()
}
