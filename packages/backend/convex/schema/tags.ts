import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const tagsTables = {
    tags: defineTable({
        userId: v.string(),
        name: v.string(),
        color: v.string(), // hex color
    })
        .index('by_userId', ['userId'])
        .index('by_userId_and_name', ['userId', 'name']),
}
