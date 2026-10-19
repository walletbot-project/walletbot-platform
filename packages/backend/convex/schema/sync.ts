import { defineTable } from 'convex/server'
import { v } from 'convex/values'

// One row per user. Mutations that touch user-owned data must atomically
// increment `value` and stamp the affected rows / tombstones with the new
// value as their `seq`.
export const syncCounters = defineTable({
    userId: v.string(),
    value: v.int64(),
}).index('by_user', ['userId'])

// Soft-delete record. When a user-owned row is deleted, the row is removed
// and a tombstone is written so syncing clients can mirror the deletion.
export const syncedTable = v.union(
    v.literal('accounts'),
    v.literal('categories'),
    v.literal('transactions'),
    v.literal('tags'),
    v.literal('transactionTags'),
    v.literal('savedFilters'),
    v.literal('dashboardWidgets'),
    // Added in the v3 → v4 native schema bump (agent memory). Wire change:
    // minSupportedVersion and the Drift schemaVersion moved together.
    v.literal('agentMemories'),
    // Added in v5; projected out for supported v4 clients (0.3.x).
    v.literal('recurrences'),
)

export const tombstones = defineTable({
    userId: v.string(),
    tableName: syncedTable,
    entityId: v.string(), // the deleted row's client-side uuid
    seq: v.int64(),
    deletedAt: v.int64(),
    // Only set for `tableName === 'accounts'` tombstones written by the
    // duplicate-account auto-merge (WAL-148): the client id of the account
    // this one's data was folded into. Lets `resolveAccountId` redirect a
    // reference to the merged-away id onto the live account instead of
    // failing a lookup. Not exposed over the sync wire — purely a
    // server-side bookkeeping field.
    mergedIntoId: v.optional(v.string()),
})
    .index('by_user_seq', ['userId', 'seq'])
    .index('by_user_table_entity', ['userId', 'tableName', 'entityId'])

// Why a pushed row could not be stored as the device sent it. What the
// server does instead for each one is documented in v1/sync/internal.ts.
export const syncConflictReason = v.union(
    v.literal('account_currency_changed'),
    v.literal('tag_self_parent'),
    v.literal('tag_parent_missing'),
    v.literal('transaction_account_missing'),
    v.literal('transaction_currency_mismatch'),
    v.literal('transaction_category_missing'),
    v.literal('transaction_invalid_transfer'),
    v.literal('transaction_invalid_adjustment'),
    v.literal('join_invalid_id'),
    v.literal('join_parent_missing'),
)

export const syncConflictResolution = v.union(
    // Stored with a fix; the device's other changes survive.
    v.literal('repaired'),
    // The server's own copy was sent back over the device's.
    v.literal('reverted'),
    // Deleted, because the server had no copy to fall back to.
    v.literal('dropped'),
)

// The lasting record of a pushed row the server resolved instead of failing
// the batch, i.e. of data a device lost. Convex logs only reach back a few
// hours. One row per entity: a device that sends the same bad row again
// bumps `count` instead of growing the table.
export const syncConflicts = defineTable({
    userId: v.string(),
    tableName: syncedTable,
    entityId: v.string(),
    reason: syncConflictReason,
    resolution: syncConflictResolution,
    count: v.number(),
    firstSeenAt: v.number(),
    lastSeenAt: v.number(),
}).index('by_user_table_entity', ['userId', 'tableName', 'entityId'])
