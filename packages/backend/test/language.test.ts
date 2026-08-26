// Unit tests for the language-preference rules, outside convex/ so the Convex
// bundler never sees them. Everything under test is pure (no ctx, no fetch):
// the precedence rule that decides what a language report writes, and the
// fallback chain that picks the locale an outbound email renders in.

import { describe, expect, it } from 'vitest'
import { resolveOutboundLocale } from '../convex/emails/utils'
import { resolveLanguageWrite } from '../convex/v1/users/utils'

describe('resolveLanguageWrite', () => {
    it('writes the report when there is no row yet', () => {
        expect(
            resolveLanguageWrite({
                stored: null,
                incoming: { language: 'en', source: 'device', tag: 'en-GB' },
            }),
        ).toEqual({
            language: 'en',
            languageSource: 'device',
            languageTag: 'en-GB',
        })
    })

    it('lets an explicit pick replace an inferred value', () => {
        expect(
            resolveLanguageWrite({
                stored: {
                    language: 'en',
                    languageSource: 'device',
                    languageTag: 'en-GB',
                },
                incoming: { language: 'es', source: 'explicit', tag: 'es' },
            }),
        ).toEqual({
            language: 'es',
            languageSource: 'explicit',
            languageTag: 'es',
        })
    })

    // The reason this rule exists: pick Spanish in the app, then open the web
    // app on an English laptop, and email must stay Spanish.
    it('refuses to let another device overwrite an explicit pick', () => {
        expect(
            resolveLanguageWrite({
                stored: {
                    language: 'es',
                    languageSource: 'explicit',
                    languageTag: 'es',
                },
                incoming: { language: 'en', source: 'device', tag: 'en-US' },
            }),
        ).toBeNull()
    })

    it('lets an explicit pick replace another explicit pick', () => {
        expect(
            resolveLanguageWrite({
                stored: {
                    language: 'es',
                    languageSource: 'explicit',
                    languageTag: 'es',
                },
                incoming: { language: 'en', source: 'explicit', tag: 'en' },
            }),
        ).toEqual({
            language: 'en',
            languageSource: 'explicit',
            languageTag: 'en',
        })
    })

    // Choosing "System" in the picker reports as `device`, which is how a user
    // hands control back to the OS after an explicit pick.
    it('accepts a device report over an inferred value', () => {
        expect(
            resolveLanguageWrite({
                stored: {
                    language: 'es',
                    languageSource: 'device',
                    languageTag: 'es-AR',
                },
                incoming: { language: 'en', source: 'device', tag: 'en-US' },
            }),
        ).toEqual({
            language: 'en',
            languageSource: 'device',
            languageTag: 'en-US',
        })
    })

    it('writes nothing when the report changes nothing', () => {
        const stored = {
            language: 'es' as const,
            languageSource: 'device' as const,
            languageTag: 'es-AR',
        }
        expect(
            resolveLanguageWrite({
                stored,
                incoming: { language: 'es', source: 'device', tag: 'es-AR' },
            }),
        ).toBeNull()
    })

    // Same language, finer tag: worth writing, since the tag is what outbound
    // messages format numbers and dates with.
    it('writes when only the region changed', () => {
        expect(
            resolveLanguageWrite({
                stored: {
                    language: 'es',
                    languageSource: 'device',
                    languageTag: 'es',
                },
                incoming: { language: 'es', source: 'device', tag: 'es-AR' },
            }),
        ).toEqual({
            language: 'es',
            languageSource: 'device',
            languageTag: 'es-AR',
        })
    })

    it('omits the tag entirely when the report has none', () => {
        expect(
            resolveLanguageWrite({
                stored: null,
                incoming: { language: 'es', source: 'device' },
            }),
        ).toEqual({ language: 'es', languageSource: 'device' })
    })

    // A row written before the language fields existed.
    it('treats a row with no language as unset', () => {
        expect(
            resolveLanguageWrite({
                stored: {},
                incoming: { language: 'en', source: 'device', tag: 'en' },
            }),
        ).toEqual({
            language: 'en',
            languageSource: 'device',
            languageTag: 'en',
        })
    })
})

describe('resolveOutboundLocale', () => {
    it('prefers the stored language over everything else', () => {
        expect(
            resolveOutboundLocale({
                stored: 'en',
                hint: 'es',
                acceptLanguage: 'es-AR',
            }),
        ).toBe('en')
    })

    it('falls back to the caller hint when nothing is stored', () => {
        expect(resolveOutboundLocale({ stored: null, hint: 'en' })).toBe('en')
    })

    it('falls back to the request header when there is no hint', () => {
        expect(
            resolveOutboundLocale({
                stored: null,
                acceptLanguage: 'en-GB,en;q=0.9',
            }),
        ).toBe('en')
    })

    // A tag the product doesn't ship resolves to English, NOT to the default.
    it('resolves an unshipped language to English', () => {
        expect(
            resolveOutboundLocale({ acceptLanguage: 'pt-BR,pt;q=0.9' }),
        ).toBe('en')
    })

    // Every one of these emails was Spanish before it could be localized, so a
    // send with no signal at all must stay Spanish.
    it('defaults to Spanish when there is no signal', () => {
        expect(resolveOutboundLocale({})).toBe('es')
        expect(
            resolveOutboundLocale({
                stored: null,
                hint: null,
                acceptLanguage: null,
            }),
        ).toBe('es')
    })

    it('reads a regional Spanish header as Spanish', () => {
        expect(resolveOutboundLocale({ acceptLanguage: 'es-AR' })).toBe('es')
    })
})
