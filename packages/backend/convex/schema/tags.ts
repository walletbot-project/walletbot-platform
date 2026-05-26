import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const tags = defineTable({
    userId: v.string(),
    id: v.string(), // client-side uuid
    name: v.string(),
    description: v.optional(v.string()),
    parentId: v.optional(v.string()), // uuid of parent tag
    color: v.optional(v.string()), // hex
    archived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
    seq: v.int64(),
})
    .index('by_user_seq', ['userId', 'seq'])
    .index('by_user_id', ['userId', 'id'])
    .index('by_user_parent', ['userId', 'parentId'])
    .index('by_user_archived', ['userId', 'archived'])
