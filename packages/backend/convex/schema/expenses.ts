import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const expensesTables = {
    expenses: defineTable({
        userId: v.string(),
        amount: v.number(), // in cents to avoid floating-point issues
        currency: v.string(), // ISO 4217 (e.g. "USD")
        description: v.string(),
        category: v.string(),
        date: v.string(), // YYYY-MM-DD
    })
        .index('by_userId', ['userId'])
        .index('by_userId_date', ['userId', 'date'])
        .index('by_userId_category', ['userId', 'category']),
}
