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
