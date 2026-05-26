import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const transactions = defineTable({
    userId: v.string(),
    id: v.string(), // client-side uuid

    type: v.union(
        v.literal('expense'),
        v.literal('income'),
        v.literal('transfer'),
        v.literal('balance_adjustment'),
    ),
    name: v.string(),
    description: v.optional(v.string()),
    status: v.union(v.literal('pending'), v.literal('cleared')),
    date: v.int64(), // ms since epoch
    accountId: v.string(), // uuid of account
    categoryId: v.string(), // uuid of category
    amount: v.int64(), // cents
    currency: v.string(),

    // Transfers
    toAccountId: v.optional(v.string()),
    toAmount: v.optional(v.int64()),
    toCurrency: v.optional(v.string()),
    exchangeRate: v.optional(v.number()), // float

    // Balance adjustments
    balanceAfter: v.optional(v.int64()), // cents

    archived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
    seq: v.int64(),
})
    .index('by_user_seq', ['userId', 'seq'])
    .index('by_user_id', ['userId', 'id'])
    .index('by_user_date', ['userId', 'date'])
    .index('by_user_status', ['userId', 'status'])
    .index('by_user_type', ['userId', 'type'])
    .index('by_user_account_date', ['userId', 'accountId', 'date'])
    .index('by_user_category_date', ['userId', 'categoryId', 'date'])
    .index('by_user_to_account', ['userId', 'toAccountId'])
