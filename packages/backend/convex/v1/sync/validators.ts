import { v } from 'convex/values'
import { syncedTable } from '../../schema/sync'

const accountUpsert = v.object({
    id: v.string(),
    name: v.string(),
    currency: v.string(),
    description: v.optional(v.string()),
    color: v.string(),
    icon: v.string(),
    // Optional for backward-compat: clients from before v6 never send it;
    // replacement preserves the stored order (see applyAccountUpsert).
    position: v.optional(v.number()),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const categoryUpsert = v.object({
    id: v.string(),
    name: v.string(),
    description: v.optional(v.string()),
    color: v.string(),
    icon: v.string(),
    // Optional for backward-compat, like `accountUpsert.position`.
    position: v.optional(v.number()),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const tagUpsert = v.object({
    id: v.string(),
    name: v.string(),
    description: v.optional(v.string()),
    parentId: v.optional(v.string()),
    color: v.string(),
    // Optional for backward-compat, like `accountUpsert.position`.
    position: v.optional(v.number()),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const transactionUpsert = v.object({
    id: v.string(),
    type: v.union(
        v.literal('expense'),
        v.literal('income'),
        v.literal('transfer'),
        v.literal('balance_adjustment'),
    ),
    name: v.string(),
    description: v.optional(v.string()),
    status: v.union(v.literal('pending'), v.literal('cleared')),
    date: v.int64(),
    // Optional for backward-compat: older clients don't send it. Defaults to
    // true on insert (matches the column default).
    dateConfirmed: v.optional(v.boolean()),
    timeStatus: v.optional(
        v.union(
            v.literal('confirmed'),
            v.literal('approximation'),
            v.literal('none'),
        ),
    ),
    accountId: v.string(),
    categoryId: v.string(),
    amount: v.int64(),
    currency: v.string(),
    toAccountId: v.optional(v.string()),
    toAmount: v.optional(v.int64()),
    toCurrency: v.optional(v.string()),
    exchangeRate: v.optional(v.number()),
    balanceAfter: v.optional(v.int64()),
    // Set on an occurrence of a recurring rule; absent on a one-off. Optional
    // for backward-compat, like `dateConfirmed` above: a client from before
    // v5 simply never sends them; replacement preserves the stored link.
    recurrenceId: v.optional(v.string()),
    recurrenceIndex: v.optional(v.int64()),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const recurrenceUpsert = v.object({
    id: v.string(),
    frequency: v.union(
        v.literal('daily'),
        v.literal('weekly'),
        v.literal('monthly'),
        v.literal('yearly'),
        v.literal('customDays'),
    ),
    dayInterval: v.optional(v.int64()),
    anchorDate: v.int64(),
    endDate: v.optional(v.int64()),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const transactionTagUpsert = v.object({
    id: v.string(),
    transactionId: v.string(),
    tagId: v.string(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const savedFilterUpsert = v.object({
    id: v.string(),
    name: v.string(),
    config: v.string(),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const dashboardWidgetUpsert = v.object({
    id: v.string(),
    type: v.string(),
    filterId: v.optional(v.string()),
    position: v.number(),
    width: v.string(),
    options: v.string(),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const agentMemoryUpsert = v.object({
    id: v.string(),
    content: v.string(),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
})

const tombstoneArg = v.object({
    tableName: syncedTable,
    entityId: v.string(),
    deletedAt: v.int64(),
})

// Shared by the public `push` (mutations.ts) and the sub-transaction that
// applies its batch (internal.ts:applyPushBatch).
export const pushUpserts = v.object({
    accounts: v.optional(v.array(accountUpsert)),
    categories: v.optional(v.array(categoryUpsert)),
    tags: v.optional(v.array(tagUpsert)),
    recurrences: v.optional(v.array(recurrenceUpsert)),
    transactions: v.optional(v.array(transactionUpsert)),
    transactionTags: v.optional(v.array(transactionTagUpsert)),
    savedFilters: v.optional(v.array(savedFilterUpsert)),
    dashboardWidgets: v.optional(v.array(dashboardWidgetUpsert)),
    agentMemories: v.optional(v.array(agentMemoryUpsert)),
})

export const pushTombstones = v.optional(v.array(tombstoneArg))
