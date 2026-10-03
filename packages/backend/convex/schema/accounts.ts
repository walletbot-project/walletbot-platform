import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const accounts = defineTable({
    userId: v.string(),
    id: v.string(), // client-side uuid (separate from Convex `_id`)
    name: v.string(),
    currency: v.string(),
    description: v.optional(v.string()),
    color: v.string(), // hex; always set (default applied on write)
    icon: v.string(), // icon name; always set (default applied on write)
    // User-chosen list order; absent until the user first reorders. See
    // `compareByPosition` in @wallet-bot/shared for how absent rows sort.
    position: v.optional(v.number()),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
    seq: v.int64(), // per-user global counter at last mutation
})
    .index('by_user_seq', ['userId', 'seq'])
    .index('by_user_id', ['userId', 'id'])
    .index('by_user_archived', ['userId', 'isArchived'])
    .index('by_user_currency', ['userId', 'currency'])
