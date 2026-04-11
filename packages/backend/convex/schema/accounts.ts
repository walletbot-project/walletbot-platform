import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const accountsTables = {
    accounts: defineTable({
        userId: v.string(),
        name: v.string(),
        type: v.union(v.literal('asset'), v.literal('liability')),
        icon: v.string(),
        isDefault: v.boolean(),
        sortOrder: v.number(),
        currency: v.string(),
    })
        .index('by_userId', ['userId'])
        .index('by_userId_and_isDefault', ['userId', 'isDefault']),
}
