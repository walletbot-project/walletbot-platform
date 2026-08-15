import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const featureFlags = defineTable({
    key: v.string(),
    description: v.string(),
    enabledByDefault: v.boolean(),
    updatedAt: v.int64(),
    updatedBy: v.string(),
}).index('by_key', ['key'])

export const featureFlagOverrides = defineTable({
    flagKey: v.string(),
    userId: v.string(),
    enabled: v.boolean(),
    updatedAt: v.int64(),
    updatedBy: v.string(),
})
    .index('by_flag_user', ['flagKey', 'userId'])
    .index('by_user', ['userId'])

export const admins = defineTable({
    userId: v.string(),
    email: v.string(),
    createdAt: v.int64(),
}).index('by_user_id', ['userId'])
