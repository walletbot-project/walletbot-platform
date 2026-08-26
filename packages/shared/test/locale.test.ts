// The locale rules every layer now shares: the web catalog picker, the native
// config banners, the legal document URLs and the outbound email templates all
// resolve through these, so a change here moves all four at once.

import { describe, expect, it } from 'vitest'
import { firstLanguageTag, isLocale, resolveLocale } from '../src/locale'

describe('resolveLocale', () => {
    it('reads Spanish and its regional variants as Spanish', () => {
        expect(resolveLocale('es')).toBe('es')
        expect(resolveLocale('es-AR')).toBe('es')
        expect(resolveLocale('es-419')).toBe('es')
        expect(resolveLocale('ES-MX')).toBe('es')
        expect(resolveLocale('es_AR')).toBe('es')
        expect(resolveLocale('  es-ES  ')).toBe('es')
    })

    it('reads a full Accept-Language header off its first tag', () => {
        expect(resolveLocale('es-AR,es;q=0.9,en;q=0.8')).toBe('es')
        expect(resolveLocale('en-GB,en;q=0.9,es;q=0.8')).toBe('en')
    })

    // Anything we don't ship a catalog for falls back to English, including
    // languages that are neither.
    it('falls back to English for everything else', () => {
        expect(resolveLocale('en')).toBe('en')
        expect(resolveLocale('pt-BR')).toBe('en')
        expect(resolveLocale('fr')).toBe('en')
        expect(resolveLocale('')).toBe('en')
        expect(resolveLocale(undefined)).toBe('en')
        expect(resolveLocale(null)).toBe('en')
    })

    // `esperanto` starts with "es" and is not Spanish. Documenting it rather
    // than fixing it: matching on the `es` prefix is what every layer did
    // before this module existed, and `eo` is the real Esperanto tag anyway.
    it('is prefix-based, so eo-style false positives are possible', () => {
        expect(resolveLocale('esperanto')).toBe('es')
    })
})

describe('firstLanguageTag', () => {
    it('takes the most-preferred tag out of a header', () => {
        expect(firstLanguageTag('es-AR,es;q=0.9,en;q=0.8')).toBe('es-AR')
        expect(firstLanguageTag('en-GB')).toBe('en-GB')
        expect(firstLanguageTag('es;q=0.9')).toBe('es')
        expect(firstLanguageTag(' es-AR , en ')).toBe('es-AR')
    })

    it('answers null when there is nothing usable', () => {
        expect(firstLanguageTag('')).toBeNull()
        expect(firstLanguageTag('   ')).toBeNull()
        expect(firstLanguageTag(undefined)).toBeNull()
        expect(firstLanguageTag(null)).toBeNull()
    })
})

describe('isLocale', () => {
    it('accepts only the shipped locales', () => {
        expect(isLocale('es')).toBe(true)
        expect(isLocale('en')).toBe(true)
        expect(isLocale('es-AR')).toBe(false)
        expect(isLocale('pt')).toBe(false)
        expect(isLocale('')).toBe(false)
    })
})
