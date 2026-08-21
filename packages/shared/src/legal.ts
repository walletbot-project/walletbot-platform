/**
 * Legal-documents versioning policy. A document version is its
 * "Última actualización" date (ISO `YYYY-MM-DD`), so versions compare as plain
 * strings. The three knobs below are the production controls — the whole
 * publishing workflow is: edit the four documents in docs/legal/ (ES and EN
 * together), set the new date here as CURRENT, choose a grace deadline, and
 * deploy the backend. Installed clients pick the policy up over the wire
 * (v1/legal verdicts for remote accounts, the /v1/config payload for native
 * local accounts); no app release is involved. See
 * docs/legal/README.md § Versioning & re-acceptance.
 */

/**
 * The newest published documents — what the sign-up checkboxes and the
 * acceptance gates display and what `v1/legal/mutations:accept` records.
 */
export const CURRENT_LEGAL_VERSION = '2026-08-06'

/**
 * Hard floor: acceptances of versions older than this are void with no grace.
 * Raise it only for extraordinary "the old terms are legally dead" cases;
 * routine updates leave it alone and rely on the grace deadline instead.
 */
export const MIN_ACCEPTED_LEGAL_VERSION = '2026-08-06'

/**
 * Instant (ms epoch) when acceptances between MIN and CURRENT stop being
 * valid. `null` deliberately means the grace never ends: forgetting to set a
 * deadline when bumping CURRENT yields an eternal dismissible prompt, never
 * an accidental lockout. Hard blocking is always an explicit act — either a
 * deadline set here coming due, or a MIN bump.
 */
export const LEGAL_GRACE_ENDS_AT: number | null = null

export type LegalPolicy = {
    currentVersion: string
    minVersion: string
    graceEndsAt: number | null
}

export const LEGAL_POLICY: LegalPolicy = {
    currentVersion: CURRENT_LEGAL_VERSION,
    minVersion: MIN_ACCEPTED_LEGAL_VERSION,
    graceEndsAt: LEGAL_GRACE_ENDS_AT,
}

const LEGAL_VERSION_PATTERN = /^\d{4}-\d{2}-\d{2}$/

export const isValidLegalVersion = (value: string): boolean =>
    LEGAL_VERSION_PATTERN.test(value)

// Misconfigured policy must fail the deploy, not ship: Convex analyzes
// modules at push time, so throwing here rejects the push loudly.
if (
    !isValidLegalVersion(CURRENT_LEGAL_VERSION) ||
    !isValidLegalVersion(MIN_ACCEPTED_LEGAL_VERSION) ||
    MIN_ACCEPTED_LEGAL_VERSION > CURRENT_LEGAL_VERSION
) {
    throw new Error(
        'Invalid legal policy: versions must be YYYY-MM-DD and min <= current',
    )
}

/**
 * The gate decision. Mirrored in Dart
 * (apps/native/lib/legal/terms_acceptance.dart `legalVerdict`) — keep both in
 * sync.
 */
export type LegalVerdictStatus = 'ok' | 'reacceptRequested' | 'reacceptRequired'

/**
 * Pure verdict over a user's newest accepted version:
 *
 * - accepted the current (or a newer) version → `ok`;
 * - never accepted, or accepted below the min floor → `reacceptRequired`
 *   (blocking gate);
 * - accepted an old-but-valid version → `reacceptRequested` (dismissible
 *   prompt) while the grace runs, `reacceptRequired` once it expires.
 *
 * Clients must render any status they do not recognize as
 * `reacceptRequested` — an unknown future state degrades to the soft prompt,
 * never to a hard block.
 */
export function legalVerdict(
    acceptedVersion: string | null,
    policy: LegalPolicy,
    now: number,
): LegalVerdictStatus {
    if (acceptedVersion !== null && acceptedVersion >= policy.currentVersion) {
        return 'ok'
    }
    if (acceptedVersion === null || acceptedVersion < policy.minVersion) {
        return 'reacceptRequired'
    }
    if (policy.graceEndsAt === null || now < policy.graceEndsAt) {
        return 'reacceptRequested'
    }
    return 'reacceptRequired'
}

export type LegalLocale = 'es' | 'en'

/** Public URLs of the published legal documents for a locale. */
export const legalUrls = (
    locale: LegalLocale,
): { terms: string; privacy: string } => ({
    terms: `https://www.walletbot.live/${locale}/terms`,
    privacy: `https://www.walletbot.live/${locale}/privacy`,
})
