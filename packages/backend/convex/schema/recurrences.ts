import { defineTable } from 'convex/server'
import { v } from 'convex/values'

// A recurring rule: the thing the user set up once, of which every upcoming
// movement is an occurrence. Synced to native like any other user-owned entity
// (schema/sync.ts `syncedTable`, native Drift `recurrences` — the v4 → v5
// coordinated bump).
//
// The rule is stored, the occurrences are *materialised* as ordinary rows in
// `transactions` carrying `recurrenceId` (see docs/recurrency-design.md §2.5
// and §5.2). Deliberately, the rule holds only what cannot be derived from
// those rows:
//
//   - how many exist  -> count the transactions in the series
//   - how far covered -> the latest date among them
//
// Keeping those out avoids a second source of truth that could disagree with
// the rows after an edit.
export const recurrences = defineTable({
    userId: v.string(),
    id: v.string(), // client-side uuid

    frequency: v.union(
        v.literal('daily'),
        v.literal('weekly'),
        v.literal('monthly'),
        v.literal('yearly'),
        v.literal('customDays'),
    ),
    /** Only meaningful for `customDays`. */
    dayInterval: v.optional(v.int64()),
    /**
     * The first occurrence's date. Every later one is projected from *here*,
     * by index, never from its predecessor — that is what keeps a February
     * clipped to the 28th from dragging March with it
     * (docs/recurrency-design.md §2.3).
     */
    anchorDate: v.int64(),
    /** Inclusive. Absent means open-ended, capped by the frequency's batch. */
    endDate: v.optional(v.int64()),

    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
    seq: v.int64(),
})
    .index('by_user_seq', ['userId', 'seq'])
    .index('by_user_id', ['userId', 'id'])
    .index('by_user_archived', ['userId', 'isArchived'])
