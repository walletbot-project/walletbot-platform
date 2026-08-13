import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const userSettings = defineTable({
    userId: v.string(),
    defaultCurrency: v.string(),
    updatedAt: v.int64(),
}).index('by_user', ['userId'])
