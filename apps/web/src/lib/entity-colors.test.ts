import { describe, expect, it } from 'vitest'
import { COLOR_OPTIONS, foregroundOn, readableAccent } from './entity-colors'

// Expected dark-mode paint for every palette accent. The same table backs
// apps/native/test/components/readable_accent_test.dart, so both platforms
// paint the same hex for the same stored color.
const DARK_PALETTE: Record<string, string> = {
    '#69F0AE': '#9AFFC9',
    '#26A69A': '#5EB5AB',
    '#42A5F5': '#6EB8F8',
    '#FFCA28': '#FEE39F',
    '#FF7043': '#FE9574',
    '#AB47BC': '#B567C3',
    '#78909C': '#8EA2AB',
    '#3B82F6': '#5F98F5',
    '#14B8A6': '#61C7B7',
    '#F59E0B': '#FDB760',
    '#EF4444': '#F36D66',
    '#6366F1': '#7780EF',
    '#8B5CF6': '#997BF4',
    '#10B981': '#5FC799',
    '#EC4899': '#F270AA',
    '#06B6D4': '#60C6DE',
    '#84CC16': '#A1DC63',
    '#F43F5E': '#F86B7A',
    '#0EA5E9': '#5AB7EE',
    '#D946EF': '#E172F2',
    '#F97316': '#FE9258',
}

describe('readableAccent', () => {
    it('returns every stored accent unchanged in light mode', () => {
        for (const color of COLOR_OPTIONS) {
            expect(readableAccent(color, 'light')).toBe(color)
        }
    })

    it('returns #RRGGBB in dark mode so alpha suffixes still work', () => {
        for (const color of COLOR_OPTIONS) {
            expect(readableAccent(color, 'dark')).toMatch(/^#[0-9A-F]{6}$/)
        }
    })

    it('paints every palette accent as the shared dark table', () => {
        expect(Object.keys(DARK_PALETTE)).toEqual([...COLOR_OPTIONS])
        for (const color of COLOR_OPTIONS) {
            expect(readableAccent(color, 'dark')).toBe(DARK_PALETTE[color])
        }
    })

    it('stays in range for colors outside the palette', () => {
        expect(readableAccent('#FFFFFF', 'dark')).toBe('#FFFFFF')
        expect(readableAccent('#000000', 'dark')).toBe('#010101')
    })

    it('passes non-hex colors through unchanged', () => {
        expect(readableAccent('var(--x)', 'dark')).toBe('var(--x)')
    })
})

describe('foregroundOn', () => {
    // Expected values computed with the native `foregroundOn`
    // (apps/native/lib/components/color_utils.dart), so both platforms agree.
    it('picks black on saturated mid-light accents like native', () => {
        expect(foregroundOn('#D946EF')).toBe('#000000')
        expect(foregroundOn('#FFCA28')).toBe('#000000')
        expect(foregroundOn('#EF4444')).toBe('#000000')
        expect(foregroundOn('#6366F1')).toBe('#000000')
    })

    it('picks white on dark accents', () => {
        expect(foregroundOn('#000000')).toBe('#ffffff')
        expect(foregroundOn('#3B3B3B')).toBe('#ffffff')
    })
})
