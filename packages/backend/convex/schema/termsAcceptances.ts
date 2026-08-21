import { defineTable } from 'convex/server'
import { v } from 'convex/values'

/**
 * One row per (user, documents version): an affirmative acceptance of the
 * Terms & Conditions + Privacy Policy. Append-only — a new documents version
 * requires a new row, and the absence of a row for the version currently in
 * force means the user must be (re-)prompted. Merely displaying the documents
 * is never recorded (docs/legal/README.md, implementation TODO #8).
 *
 * Not a synced table: read/written only through `v1/legal` and the signup
 * hooks, so it forces no sync-contract or drift schema bump.
 */
export const termsAcceptances = defineTable({
    userId: v.string(),
    documentVersion: v.string(),
    acceptedAt: v.int64(),
    source: v.union(v.literal('signup'), v.literal('gate')),
}).index('by_user_version', ['userId', 'documentVersion'])
