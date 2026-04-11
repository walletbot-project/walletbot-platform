import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const recurrencesTables = {
    recurrences: defineTable({
        userId: v.string(),
        // Template fields — same shape as a transaction minus date
        type: v.union(
            v.literal('expense'),
            v.literal('income'),
            v.literal('transfer'),
        ),
        amount: v.number(),
        currency: v.string(),
        description: v.string(),
        categoryId: v.optional(v.id('categories')),
        tags: v.array(v.id('tags')),
        fromAccountId: v.optional(v.id('accounts')),
        toAccountId: v.optional(v.id('accounts')),
        notes: v.optional(v.string()),
        // Recurrence config
        frequency: v.union(
            v.literal('daily'),
            v.literal('weekly'),
            v.literal('monthly'),
            v.literal('yearly'),
        ),
        interval: v.number(), // every N frequency units
        startDate: v.string(), // YYYY-MM-DD
        endDate: v.optional(v.string()), // null = forever
        lastGeneratedDate: v.optional(v.string()),
        isActive: v.boolean(),
    })
        .index('by_userId', ['userId'])
        .index('by_isActive_and_lastGeneratedDate', [
            'isActive',
            'lastGeneratedDate',
        ]),
}
