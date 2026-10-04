import { defineTable } from 'convex/server'
import { v } from 'convex/values'

// Registry of identities observed using AI, not an authentication table.
// appUserId is stable independently of type and optional authenticated userId:
// a future promotion can link the same row without replacing its local ID.
// parentId records the originating installation, never a verified person.
export const appUsers = defineTable({
    appUserId: v.string(),
    type: v.union(v.literal('local'), v.literal('registered')),
    userId: v.optional(v.string()),
    parentId: v.optional(v.string()),
    createdAt: v.number(),
    lastSeenAt: v.number(),
})
    .index('by_appUserId', ['appUserId'])
    .index('by_userId', ['userId'])
    .index('by_parentId', ['parentId'])
