import { v } from 'convex/values'
import { internal } from '../../_generated/api'
import { action } from '../../_generated/server'
import { createLiveToken } from '../../live/createToken'
import { requireAuth } from '../../users/helpers'

// Wire validators for the client-built context payload (§ USER_CONTEXT in
// live/createToken.ts). Everything is optional: old builds send nothing and
// get the base prompt. The server re-sanitizes and caps the payload before
// rendering (sanitizeAgentContext) — these validators only shape the wire.
const contextValidator = v.object({
    userName: v.optional(v.string()),
    userEmail: v.optional(v.string()),
    settings: v.optional(
        v.object({
            defaultCurrency: v.optional(v.string()),
            language: v.optional(v.string()),
            theme: v.optional(v.string()),
        }),
    ),
    accounts: v.optional(
        v.array(
            v.object({
                id: v.string(),
                name: v.string(),
                currency: v.string(),
                isArchived: v.optional(v.boolean()),
            }),
        ),
    ),
    categories: v.optional(
        v.array(v.object({ id: v.string(), name: v.string() })),
    ),
    tags: v.optional(
        v.array(
            v.object({
                id: v.string(),
                name: v.string(),
                parentId: v.optional(v.string()),
            }),
        ),
    ),
    recentTransactions: v.optional(
        v.array(
            v.object({
                name: v.string(),
                amount: v.number(),
                currency: v.string(),
                type: v.string(),
                account: v.optional(v.string()),
                category: v.optional(v.string()),
                date: v.string(),
            }),
        ),
    ),
    memories: v.optional(
        v.array(v.object({ id: v.string(), content: v.string() })),
    ),
})

/// V1 client contract for provisioning a constrained Gemini Live token.
///
/// All args are optional so builds that predate a field keep minting; the
/// context payload is the client's own snapshot of its data (native reads
/// Drift, web its Convex queries) — the server validates and caps it, it
/// never reads the database for the prompt.
export const requestLiveToken = action({
    args: {
        platform: v.optional(v.string()),
        appVersion: v.optional(v.string()),
        locale: v.optional(v.string()),
        timezone: v.optional(v.string()),
        timezoneOffsetMinutes: v.optional(v.number()),
        context: v.optional(contextValidator),
    },
    handler: async (ctx, args) => {
        const startedAt = Date.now()
        // Flag-gated tools are resolved server-side, never taken from the
        // client: the mint decides what the session may call.
        const userId = await requireAuth(ctx)
        const flags = await ctx.runQuery(
            internal.featureFlags.internal.resolveFlagsForUserInternal,
            { userId },
        )

        const result = await createLiveToken({
            platform: args.platform,
            appVersion: args.appVersion,
            locale: args.locale,
            timezone: args.timezone,
            timezoneOffsetMinutes: args.timezoneOffsetMinutes,
            context: args.context,
            flags,
        })
        return {
            ...result,
            timings: {
                ...result.timings,
                actionMs: Date.now() - startedAt,
            },
        }
    },
})
