import {
    AI_CONSENT_DOCUMENT,
    AI_CONSENT_VERSION,
    isLegalVersionAtLeast,
    LEGAL_DOCUMENTS,
    LEGAL_VERSIONS,
    type LegalDocument,
    type LegalDocumentStatus,
    legalDocumentStatus,
} from '@wallet-bot/shared'
import type { MutationCtx, QueryCtx } from '../_generated/server'

export type LegalDocumentAcceptance = {
    status: LegalDocumentStatus
    /** The version a fresh acceptance records. */
    current: string
    /** The floor that still grants access. */
    min: string
    /** Highest version this user ever accepted, or null. */
    accepted: string | null
    /**
     * When that acceptance was recorded, in epoch milliseconds — a `number`,
     * not the stored `int64`, so the native client can mirror the real
     * timestamp into its local record without decoding a bigint off the wire.
     * Millisecond timestamps are exact in a double.
     */
    acceptedAt: number | null
}

export type LegalAcceptanceStatus = Record<
    LegalDocument,
    LegalDocumentAcceptance
> & {
    /** Some document was never accepted at or above its floor: hard gate. */
    blocking: boolean
    /** Some document is below `current`: prompt (dismissible unless blocking). */
    prompt: boolean
}

/**
 * Highest version the user ever accepted for one document, or null.
 *
 * The index is `['userId', 'document', 'version']`, so a descending read of the
 * (userId, document) range returns the greatest version first — versions are
 * ordered strings compared lexicographically, which is exactly how Convex
 * orders them in the index. One indexed read, no scan.
 */
const latestAcceptance = async (
    ctx: QueryCtx | MutationCtx,
    userId: string,
    document: LegalDocument | typeof AI_CONSENT_DOCUMENT,
): Promise<{ version: string; acceptedAt: number } | null> => {
    const latest = await ctx.db
        .query('legalAcceptances')
        .withIndex('by_user_document_version', (q) =>
            q.eq('userId', userId).eq('document', document),
        )
        .order('desc')
        .first()
    if (!latest) return null
    return { version: latest.version, acceptedAt: Number(latest.acceptedAt) }
}

export async function resolveAcceptanceStatus(
    ctx: QueryCtx | MutationCtx,
    userId: string,
): Promise<LegalAcceptanceStatus> {
    const documents = await Promise.all(
        LEGAL_DOCUMENTS.map(async (document) => {
            const latest = await latestAcceptance(ctx, userId, document)
            const acceptance: LegalDocumentAcceptance = {
                status: legalDocumentStatus(document, latest?.version ?? null),
                current: LEGAL_VERSIONS[document].current,
                min: LEGAL_VERSIONS[document].min,
                accepted: latest?.version ?? null,
                acceptedAt: latest?.acceptedAt ?? null,
            }
            return [document, acceptance] as const
        }),
    )

    const byDocument: Record<LegalDocument, LegalDocumentAcceptance> = {
        terms: documents[0][1],
        privacy: documents[1][1],
    }

    return {
        ...byDocument,
        blocking: documents.some(([, doc]) => doc.status === 'missing'),
        prompt: documents.some(([, doc]) => doc.status !== 'current'),
    }
}

export type RecordAcceptancesArgs = {
    userId: string
    documents: LegalDocument[]
    ageConfirmed: boolean
    platform: string
    appVersion?: string
    locale?: string
}

/**
 * Writes one row per accepted document.
 *
 * The recorded version is always the server's `current` — a client never gets
 * to name the version it is accepting, so it cannot backdate an acceptance to
 * a text it never saw.
 */
export async function recordAcceptances(
    ctx: MutationCtx,
    args: RecordAcceptancesArgs,
): Promise<void> {
    if (!args.ageConfirmed) {
        throw new Error('Age confirmation is required to accept')
    }
    if (args.documents.length === 0) {
        throw new Error('No documents to accept')
    }

    const acceptedAt = BigInt(Date.now())
    // Dedup so one request cannot write the same document twice.
    for (const document of new Set(args.documents)) {
        await ctx.db.insert('legalAcceptances', {
            userId: args.userId,
            document,
            version: LEGAL_VERSIONS[document].current,
            acceptedAt,
            ageConfirmed: args.ageConfirmed,
            platform: args.platform,
            appVersion: args.appVersion,
            locale: args.locale,
        })
    }
}

/** What the signed-in user has consented to on the AI disclosure. */
export type AiConsentStatus = {
    /** Accepted `current` or newer: the agent may run. */
    accepted: boolean
    /** Highest version this user ever accepted, or null. */
    version: string | null
    acceptedAt: number | null
    /** The version a fresh consent records, and the one the sheet shows. */
    current: string
}

export async function resolveAiConsent(
    ctx: QueryCtx | MutationCtx,
    userId: string,
): Promise<AiConsentStatus> {
    const latest = await latestAcceptance(ctx, userId, AI_CONSENT_DOCUMENT)
    return {
        accepted:
            latest !== null &&
            isLegalVersionAtLeast(latest.version, AI_CONSENT_VERSION),
        version: latest?.version ?? null,
        acceptedAt: latest?.acceptedAt ?? null,
        current: AI_CONSENT_VERSION,
    }
}

export type RecordAiConsentArgs = {
    userId: string
    platform: string
    appVersion?: string
    locale?: string
}

/**
 * Records consent to send data to the AI providers.
 *
 * Append-only like every other row here, and the version written is always the
 * server's `AI_CONSENT_VERSION` — a client cannot claim to have consented to a
 * disclosure it was never shown. `ageConfirmed` is true because reaching the
 * agent requires an accepted Terms row, which carries that representation; the
 * field is about the Terms, not about this consent.
 */
export async function recordAiConsent(
    ctx: MutationCtx,
    args: RecordAiConsentArgs,
): Promise<void> {
    await ctx.db.insert('legalAcceptances', {
        userId: args.userId,
        document: AI_CONSENT_DOCUMENT,
        version: AI_CONSENT_VERSION,
        acceptedAt: BigInt(Date.now()),
        ageConfirmed: true,
        platform: args.platform,
        appVersion: args.appVersion,
        locale: args.locale,
    })
}
