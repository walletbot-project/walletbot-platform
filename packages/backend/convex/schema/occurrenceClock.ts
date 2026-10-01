import { defineTable } from 'convex/server'
import { v } from 'convex/values'

// Retired clock, retained only to accept already-deployed development data.
// No code reads or updates it.
export const occurrenceClock = defineTable({
    key: v.literal('singleton'),
    cutoff: v.int64(),
}).index('by_key', ['key'])
