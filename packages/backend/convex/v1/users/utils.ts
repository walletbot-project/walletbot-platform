import type { Locale } from '@wallet-bot/shared'

export type LanguageSource = 'device' | 'explicit'

/** The language columns as they currently stand on a `userSettings` row. */
export type StoredLanguage = {
    language?: Locale
    languageSource?: LanguageSource
    languageTag?: string
}

/** What a client just told us. */
export type LanguageReport = {
    language: Locale
    source: LanguageSource
    tag?: string
}

export type LanguageWrite = {
    language: Locale
    languageSource: LanguageSource
    languageTag?: string
}

/**
 * Decides what a language report should actually write, or `null` for "leave
 * the row alone".
 *
 * Two things this has to get right, both of which come from the same fact: the
 * language picker is device-scoped and tri-state (`system | es | en`), so
 * several devices report independently and can disagree.
 *
 * 1. An inferred (`device`) report NEVER overwrites a deliberate (`explicit`)
 *    choice. Otherwise a user who picked Spanish in the app, then opened the
 *    web app on an English laptop, would silently start receiving English
 *    email. Choosing "System" in the picker is itself a `device` report.
 *    That is how a user hands control back to the OS, and the only way an
 *    `explicit` value gets replaced is another `explicit` one.
 * 2. An unchanged report writes nothing. Clients push on every launch, and
 *    `updatedAt` is shared with `defaultCurrency`, so echoing the same value
 *    back would bump the row forever for no reason.
 */
export function resolveLanguageWrite(args: {
    stored: StoredLanguage | null
    incoming: LanguageReport
}): LanguageWrite | null {
    const { stored, incoming } = args

    if (stored?.languageSource === 'explicit' && incoming.source === 'device') {
        return null
    }

    const unchanged =
        stored?.language === incoming.language &&
        stored?.languageSource === incoming.source &&
        stored?.languageTag === incoming.tag
    if (unchanged) return null

    return {
        language: incoming.language,
        languageSource: incoming.source,
        ...(incoming.tag === undefined ? {} : { languageTag: incoming.tag }),
    }
}
