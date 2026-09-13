import { defineTable } from 'convex/server'
import { v } from 'convex/values'

// A reactive fallback for v1 web clients that do not send asOfMs.
export const occurrenceClock = defineTable({
    key: v.literal('singleton'),
    cutoff: v.int64(),
}).index('by_key', ['key'])
