// What the text-channel agent needs to know about the user before its first
// model call, in one read.
//
// The voice channel gets the equivalent from the client: the app builds a
// context snapshot and posts it to `/v1/live/token`, which sanitizes it into
// the USER_CONTEXT block (`live/createToken.ts`). A WhatsApp turn has no
// client to build one, so the server assembles the parts that cannot be
// recovered through a tool call — the memories the user expects to carry
// across channels, and the settings that decide how to address them.

import { AGENT_CONTEXT_CAPS, type Locale } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internalQuery } from '../_generated/server'
import { resolveFlagsForUser } from '../featureFlags/helpers'
import type { FlagKey } from '../featureFlags/utils'
import { getSettingsForUser } from '../v1/users/helpers'

export type AgentTurnContext = {
    memories: { id: string; content: string }[]
    defaultCurrency: string
    /** Null when no client of this account has ever reported a language. */
    language: Locale | null
    flags: Record<FlagKey, boolean>
}

export const turnContext = internalQuery({
    args: { userId: v.string() },
    handler: async (ctx, args): Promise<AgentTurnContext> => {
        // Capped by `addMemory` on both write paths, so this read is bounded
        // by design rather than by hope.
        const rows = await ctx.db
            .query('agentMemories')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', args.userId).eq('isArchived', false),
            )
            .take(AGENT_CONTEXT_CAPS.memories)
        const settings = await getSettingsForUser(ctx, args.userId)
        return {
            // Oldest first, the order `v1/memories/queries:listActive` renders
            // them in, so a memory means the same thing in both channels.
            memories: rows
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
                .map((row) => ({ id: row.id, content: row.content })),
            defaultCurrency: settings.defaultCurrency,
            language: settings.language,
            flags: await resolveFlagsForUser(ctx, args.userId),
        }
    },
})
