import { describe, expect, it } from 'vitest'
import { COLOR_OPTIONS, readableAccent } from './entity-colors'

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
