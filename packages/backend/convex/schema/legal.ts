import { defineTable } from 'convex/server'
import { v } from 'convex/values'

/**
 * Append-only log of Terms & Conditions / Privacy Policy acceptances.
 *
 * One row per acceptance event — never updated in place, so the history of
 * what a user accepted and when survives a later re-acceptance. Merely
 * *showing* a document writes nothing (docs/legal/README.md).
 *
 * Deliberately its own table rather than columns on the better-auth user row:
 * that row belongs to the auth component and is off limits.
 *
 * `version` is an ordered opaque string compared lexicographically — see
 * `@wallet-bot/shared`'s `legal.ts`. The index therefore answers "has this
 * user accepted this document at version >= X?" as one indexed range read.
 */
export const legalAcceptances = defineTable({
    userId: v.string(),
    /**
     * 'terms' | 'privacy' are the gated documents; 'ai' is the point-of-use
     * consent to send data to the AI providers. `resolveAcceptanceStatus`
     * loops `LEGAL_DOCUMENTS` and therefore never sees an 'ai' row, so the
     * launch gate is unaffected by it.
     */
    document: v.union(
        v.literal('terms'),
        v.literal('privacy'),
        v.literal('ai'),
    ),
    version: v.string(),
    acceptedAt: v.int64(),
    /** The 18+ representation the user made alongside this acceptance. */
    ageConfirmed: v.boolean(),
    /** 'web' | 'android' | 'ios' | 'macos' | 'unknown' — evidence, not a gate. */
    platform: v.string(),
    appVersion: v.optional(v.string()),
    locale: v.optional(v.string()),
}).index('by_user_document_version', ['userId', 'document', 'version'])
