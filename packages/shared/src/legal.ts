/**
 * Terms & Conditions / Privacy Policy versioning and acceptance rules.
 *
 * The documents themselves live in `docs/legal/*.md` and are published by
 * `apps/landing` at `https://www.walletbot.live/{en,es}/{terms,privacy}`.
 *
 * A version is an ORDERED opaque string — today the document's "Last updated"
 * date (`2026-08-06`), but a suffix is allowed (`2026-08-06b`). Ordering is a
 * guarantee of how versions are minted, so comparison is plain lexicographic
 * (`<`, `>=`), NEVER semver: `config/utils.ts:compareVersions` would parse
 * `2026-08-06` as major 2026 and lose the rest.
 *
 * Two constants per document:
 * - `current` — what a fresh acceptance records, and what users are prompted
 *   for.
 * - `min` — the floor that still grants access. A user who accepted anything
 *   `>= min` keeps using the app (the grace period) and is only *nudged* to
 *   accept `current`; below it, they are blocked until they accept.
 *
 * Publishing a new version:
 *  1. Edit BOTH languages of the document under `docs/legal` (its README owns
 *     that rule) and bump its "Last updated" date.
 *  2. Bump `current` here to the new date.
 *  3. Leave `min` alone — that is the grace period.
 *  4. When the grace period ends, raise `min` to the same value. Every user
 *     below it is blocked on next launch, so this is a deliberate, announced
 *     step.
 *  5. Mirror both constants in `apps/native/lib/legal/legal_versions.dart` —
 *     native needs them offline for local-only accounts. The Dart file is a
 *     bundled FALLBACK; `/v1/config` serves the authoritative values.
 */

import type { Locale } from './locale'

export const LEGAL_DOCUMENTS = ['terms', 'privacy'] as const

export type LegalDocument = (typeof LEGAL_DOCUMENTS)[number]

export type LegalDocumentVersions = {
    current: string
    min: string
}

export const LEGAL_VERSIONS: Record<LegalDocument, LegalDocumentVersions> = {
    terms: { current: '2026-08-23', min: '2026-08-23' },
    privacy: { current: '2026-08-23', min: '2026-08-23' },
}

/**
 * What the user still owes for one document.
 *
 * - `current`  — accepted `current` (or newer): nothing to ask.
 * - `outdated` — accepted at least `min` but below `current`: inside the grace
 *   period, so the prompt is dismissible.
 * - `missing`  — never accepted, or only below `min`: blocking.
 */
export type LegalDocumentStatus = 'current' | 'outdated' | 'missing'

export const isLegalDocument = (value: string): value is LegalDocument =>
    (LEGAL_DOCUMENTS as readonly string[]).includes(value)

/** Lexicographic, per the ordering guarantee above. */
export const isLegalVersionAtLeast = (
    version: string,
    floor: string,
): boolean => version >= floor

export const legalDocumentStatus = (
    document: LegalDocument,
    acceptedVersion: string | null,
): LegalDocumentStatus => {
    const { current, min } = LEGAL_VERSIONS[document]
    if (acceptedVersion === null) return 'missing'
    if (isLegalVersionAtLeast(acceptedVersion, current)) return 'current'
    return isLegalVersionAtLeast(acceptedVersion, min) ? 'outdated' : 'missing'
}

/** Locales the published documents exist in (`docs/legal/*.{en,es}.md`). */
export type LegalLocale = Locale

const LEGAL_SITE_URL = 'https://www.walletbot.live'

/**
 * Public URL of a document, as routed by `apps/landing`
 * (`src/pages/{en,es}/{privacy,terms}.astro`).
 */
export const legalDocumentUrl = (
    document: LegalDocument,
    locale: LegalLocale,
): string =>
    `${LEGAL_SITE_URL}/${locale}/${document === 'terms' ? 'terms' : 'privacy'}`
