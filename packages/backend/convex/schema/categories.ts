import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const categoriesTables = {
    categories: defineTable({
        userId: v.optional(v.string()), // null/undefined = system default
        name: v.string(), // i18n key for system, raw string for user-created
        icon: v.string(), // emoji
        color: v.string(), // hex color
        parentId: v.optional(v.id('categories')), // subcategory support
        isSystem: v.boolean(),
        sortOrder: v.number(),
    })
        .index('by_userId', ['userId'])
        .index('by_isSystem', ['isSystem'])
        .index('by_parentId', ['parentId']),
}
