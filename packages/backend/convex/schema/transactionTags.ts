import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const transactionTags = defineTable({
    userId: v.string(),
    id: v.string(), // client-side uuid for the join row itself
    transactionId: v.string(), // uuid of transaction
    tagId: v.string(), // uuid of tag
    createdAt: v.int64(),
    updatedAt: v.int64(),
    seq: v.int64(),
})
    .index('by_user_seq', ['userId', 'seq'])
    .index('by_user_id', ['userId', 'id'])
    .index('by_user_transaction_tag', ['userId', 'transactionId', 'tagId'])
    .index('by_user_transaction', ['userId', 'transactionId'])
    .index('by_user_tag', ['userId', 'tagId'])
