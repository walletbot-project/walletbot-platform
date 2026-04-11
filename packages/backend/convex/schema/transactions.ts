import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const transactionsTables = {
    transactions: defineTable({
        userId: v.string(),
        type: v.union(
            v.literal('expense'),
            v.literal('income'),
            v.literal('transfer'),
        ),
        amount: v.number(), // in cents, always positive
        currency: v.string(), // ISO 4217
        description: v.string(),
        categoryId: v.optional(v.id('categories')), // null for transfers
        tags: v.array(v.id('tags')),
        fromAccountId: v.optional(v.id('accounts')), // expense, transfer
        toAccountId: v.optional(v.id('accounts')), // income, transfer
        // Cross-currency transfers: source is amount+currency, destination is these fields
        destinationAmount: v.optional(v.number()), // cents in destination currency
        destinationCurrency: v.optional(v.string()), // ISO 4217 of destination
        date: v.string(), // YYYY-MM-DD
        notes: v.optional(v.string()),
        recurrenceId: v.optional(v.id('recurrences')), // if auto-generated
    })
        .index('by_userId', ['userId'])
        .index('by_userId_and_date', ['userId', 'date'])
        .index('by_userId_and_type', ['userId', 'type'])
        .index('by_userId_and_categoryId', ['userId', 'categoryId'])
        .index('by_userId_and_fromAccountId', ['userId', 'fromAccountId'])
        .index('by_userId_and_toAccountId', ['userId', 'toAccountId']),
}
