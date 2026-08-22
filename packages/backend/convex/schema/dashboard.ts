import { defineTable } from 'convex/server'
import { v } from 'convex/values'

// A reusable, named slice of transactions (the "Saved View" primitive from
// docs/home-dashboard.md). `config` is an opaque JSON string of the canonical
// `{combinator, children}` condition tree; the backend stores it verbatim and
// never parses it in v1.
export const savedFilters = defineTable({
    userId: v.string(),
    id: v.string(), // client-side uuid
    name: v.string(),
    config: v.string(), // JSON canonical condition tree
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
    seq: v.int64(),
})
    .index('by_user_seq', ['userId', 'seq'])
    .index('by_user_id', ['userId', 'id'])
    .index('by_user_archived', ['userId', 'isArchived'])

// One configured home-dashboard tile. `filterId` is a soft reference to a
// saved filter's client-side id (null for the balance card). `options` is an
// opaque JSON string of display options; stored verbatim, never parsed here.
//
// `type` and `width` stay plain strings on purpose: a row written by a newer
// client must survive a round-trip through an older one rather than fail
// validation. The authoritative unions are `WIDGET_TYPES` and
// `DASHBOARD_WIDTHS` in `packages/shared/src/dashboard/widgets.ts`, and both
// clients skip a value they don't recognise.
export const dashboardWidgets = defineTable({
    userId: v.string(),
    id: v.string(), // client-side uuid
    type: v.string(), // "stat" | "list" | "balance" | "chart"
    filterId: v.optional(v.string()),
    position: v.number(),
    width: v.string(), // "full" | "two_thirds" | "half" | "third"
    options: v.string(), // JSON display options
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
    seq: v.int64(),
})
    .index('by_user_seq', ['userId', 'seq'])
    .index('by_user_id', ['userId', 'id'])
    .index('by_user_archived', ['userId', 'isArchived'])
