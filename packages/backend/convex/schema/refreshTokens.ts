import { defineTable } from 'convex/server'
import { v } from 'convex/values'

// Long-lived session tokens for the native app. Not rotated — a token issued
// at sign-in stays valid until explicitly revoked (signout, "remove this
// device" action, etc.). Stored as SHA-256 hash; the raw secret is never
// persisted server-side.
export const refreshTokens = defineTable({
    // Better-auth user id (the component owns the users table, so this is a string).
    userId: v.string(),
    // SHA-256 hex of the raw session-token secret. The secret itself is never persisted.
    tokenHash: v.string(),
    // Legacy from the rotating-refresh-token design. Kept optional so existing
    // rows still validate; not written on new rows.
    family: v.optional(v.string()),
    // Legacy from the rotating-refresh-token design. Kept optional so existing
    // rows still validate; not written on new rows.
    expiresAt: v.optional(v.number()),
    createdAt: v.number(),
    revokedAt: v.optional(v.number()),
    // Legacy from the rotating-refresh-token design.
    replacedBy: v.optional(v.id('refreshTokens')),
    userAgent: v.optional(v.string()),
})
    .index('by_tokenHash', ['tokenHash'])
    .index('by_userId', ['userId'])
