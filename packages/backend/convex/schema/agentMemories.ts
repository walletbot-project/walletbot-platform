import { defineTable } from 'convex/server'
import { v } from 'convex/values'

// The agent's long-term memory: one row per durable user preference or fact
// ("if no account is stated, use Galicia"). Written by the agent's memory
// tools, injected into the mint context payload, and synced to native like
// any other user-owned entity (schema/sync.ts `syncedTable`, native Drift
// `agent_memories` — the v3 → v4 coordinated bump).
export const agentMemories = defineTable({
    userId: v.string(),
    id: v.string(), // client-side uuid
    content: v.string(),
    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
    seq: v.int64(),
})
    .index('by_user_seq', ['userId', 'seq'])
    .index('by_user_id', ['userId', 'id'])
    .index('by_user_archived', ['userId', 'isArchived'])
