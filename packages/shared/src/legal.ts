/**
 * Version identifier of the legal documents (Terms & Conditions + Privacy
 * Policy) currently in force — the "Última actualización" date shared by all
 * four files in docs/legal/. Bump it whenever the documents change in a way
 * that requires re-acceptance: recorded acceptances are compared against this
 * value and users are re-prompted when they differ.
 */
export const CURRENT_LEGAL_VERSION = '2026-08-06'

const LEGAL_VERSION_PATTERN = /^\d{4}-\d{2}-\d{2}$/

export const isValidLegalVersion = (value: string): boolean =>
    LEGAL_VERSION_PATTERN.test(value)

export type LegalLocale = 'es' | 'en'

/** Public URLs of the published legal documents for a locale. */
export const legalUrls = (
    locale: LegalLocale,
): { terms: string; privacy: string } => ({
    terms: `https://www.walletbot.live/${locale}/terms`,
    privacy: `https://www.walletbot.live/${locale}/privacy`,
})
