import { defineTable } from 'convex/server'
import { v } from 'convex/values'

// One row per "delete my account" email link. The raw token only ever exists
// inside the emailed URL; we store its SHA-256 hex, mirroring refreshTokens.
export const userDeletionRequests = defineTable({
    // Better-auth user id (the component owns the users table, so this is a string).
    userId: v.string(),
    email: v.string(),
    tokenHash: v.string(),
    expiresAt: v.number(),
    // 'pending' until the link is clicked; 'processing' once the purge is
    // scheduled. Rows are removed entirely when the purge finalizes.
    status: v.union(v.literal('pending'), v.literal('processing')),
})
    .index('by_tokenHash', ['tokenHash'])
    .index('by_email', ['email'])
    .index('by_userId', ['userId'])

// Denylist of users whose deletion has been confirmed. Rows are tiny and kept
// forever: native access JWTs are stateless with a 24h TTL and requireAuth
// never hits the DB for them, so without this check a deleted user's
// still-valid token could sync data back into existence after the purge.
export const deletedUsers = defineTable({
    userId: v.string(),
    deletedAt: v.number(),
}).index('by_userId', ['userId'])
