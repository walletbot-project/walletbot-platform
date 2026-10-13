import { paginationOptsValidator } from 'convex/server'
import { v } from 'convex/values'
import { query } from '../../_generated/server'
import { requireAdminCaller } from '../../admin/helpers'

/** Every planned field plus timers fits well under this. */
const MAX_FIELDS = 500

export const list = query({
    args: { paginationOpts: paginationOptsValidator },
    handler: async (ctx, args) => {
        await requireAdminCaller(ctx)

        const result = await ctx.db
            .query('usabilitySessions')
            .withIndex('by_number')
            .order('desc')
            .paginate(args.paginationOpts)

        return {
            ...result,
            page: result.page.map((session) => ({
                id: session._id,
                number: session.number,
                title: session.title ?? null,
                group: session.group,
                sessionDay: session.sessionDay,
                status: session.status,
                hasRecording: session.recording !== undefined,
            })),
        }
    },
})

/**
 * One session with its credentials, expected answers and every field filled
 * so far. Takes a plain string so a stale or mistyped URL renders "not found"
 * instead of failing validation.
 */
export const get = query({
    args: { sessionId: v.string() },
    handler: async (ctx, args) => {
        await requireAdminCaller(ctx)

        const sessionId = ctx.db.normalizeId(
            'usabilitySessions',
            args.sessionId,
        )
        if (!sessionId) return null
        const session = await ctx.db.get(sessionId)
        if (!session) return null

        const fields = await ctx.db
            .query('usabilityFields')
            .withIndex('by_sessionId_and_key', (q) =>
                q.eq('sessionId', sessionId),
            )
            .take(MAX_FIELDS)

        return {
            id: session._id,
            number: session.number,
            title: session.title ?? null,
            group: session.group,
            sessionDay: session.sessionDay,
            status: session.status,
            error: session.error ?? null,
            password: session.password,
            users: session.users,
            scenario2Answers: session.scenario2Answers ?? null,
            recording: session.recording
                ? {
                      name: session.recording.name,
                      size: session.recording.size,
                      contentType: session.recording.contentType ?? null,
                      uploadedAt: session.recording.uploadedAt,
                      url: await ctx.storage.getUrl(
                          session.recording.storageId,
                      ),
                  }
                : null,
            fields: fields.map((field) => ({
                key: field.key,
                value: field.value,
            })),
        }
    },
})
