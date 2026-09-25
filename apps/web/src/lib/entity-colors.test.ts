import { describe, expect, it } from 'vitest'
import { COLOR_OPTIONS, foregroundOn, readableAccent } from './entity-colors'

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

    it('is idempotent, so adapting twice paints the same color', () => {
        for (const color of COLOR_OPTIONS) {
            const once = readableAccent(color, 'dark')
            expect(readableAccent(once, 'dark')).toBe(once)
        }
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
