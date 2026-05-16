import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const refreshTokens = defineTable({
    // Better-auth user id (the component owns the users table, so this is a string).
    userId: v.string(),
    // SHA-256 hex of the raw refresh-token secret. The secret itself is never persisted.
    tokenHash: v.string(),
    // Random id shared by every rotation of the same logical token. If a revoked
    // token is presented again, every row in the family is revoked (theft detection).
    family: v.string(),
    expiresAt: v.number(),
    createdAt: v.number(),
    revokedAt: v.optional(v.number()),
    replacedBy: v.optional(v.id('refreshTokens')),
    userAgent: v.optional(v.string()),
})
    .index('by_tokenHash', ['tokenHash'])
    .index('by_userId', ['userId'])
    .index('by_family', ['family'])
