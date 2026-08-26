import { AGENT_CONTEXT_CAPS } from '@wallet-bot/shared'
import { query } from '../../_generated/server'
import { requireAuth } from '../../users/helpers'

/**
 * The user's active agent memories, oldest first (insertion order — the
 * order the prompt's Memories block renders them in). The set is capped at
 * `AGENT_CONTEXT_CAPS.memories` by the create mutation, so this read is
 * bounded by design.
 */
export const listActive = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        const rows = await ctx.db
            .query('agentMemories')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .take(AGENT_CONTEXT_CAPS.memories)
        return rows
            .slice()
            .sort((a, b) =>
                a.createdAt === b.createdAt
                    ? a.id < b.id
                        ? -1
                        : 1
                    : a.createdAt < b.createdAt
                      ? -1
                      : 1,
            )
            .map((row) => ({ id: row.id, content: row.content }))
    },
})
