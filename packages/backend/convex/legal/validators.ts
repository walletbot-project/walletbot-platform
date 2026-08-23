import { v } from 'convex/values'

/** The two documents, as a Convex validator. Mirrors `LEGAL_DOCUMENTS`. */
export const legalDocumentValidator = v.union(
    v.literal('terms'),
    v.literal('privacy'),
)

/**
 * The payload behind every acceptance, from the gate or from sign-up.
 *
 * No `version` field on purpose: the server records its own `current`, so a
 * client cannot claim to have accepted a text it was never shown.
 */
export const acceptanceInputValidator = v.object({
    documents: v.array(legalDocumentValidator),
    ageConfirmed: v.boolean(),
    platform: v.string(),
    appVersion: v.optional(v.string()),
    locale: v.optional(v.string()),
})
