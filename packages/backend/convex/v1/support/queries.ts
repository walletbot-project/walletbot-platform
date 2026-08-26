import { paginationOptsValidator } from 'convex/server'
import { v } from 'convex/values'
import { query } from '../../_generated/server'
import { requireAdmin } from '../../featureFlags/helpers'
import { requireAuth } from '../../users/helpers'

/**
 * How much of the plain-text body the list page carries per row. The full
 * bodies are capped at 512 KiB each (`support/utils.ts`), so returning them for
 * a whole page could approach Convex's per-query result limit — `list` stays a
 * metadata view and `get` returns one full message.
 */
const PREVIEW_CHARS = 280

/**
 * Inbound support mail, newest first. Admin-only: these rows hold whatever a
 * user chose to write to support, which is arbitrary personal data.
 */
export const list = query({
    args: { paginationOpts: paginationOptsValidator },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await requireAdmin(ctx, userId)

        const result = await ctx.db
            .query('supportEmails')
            .withIndex('by_receivedAt')
            .order('desc')
            .paginate(args.paginationOpts)

        return {
            ...result,
            page: result.page.map((email) => ({
                _id: email._id,
                from: email.from,
                to: email.to,
                subject: email.subject,
                receivedAt: email.receivedAt,
                attachmentCount: email.attachments.length,
                bodyTruncated: email.bodyTruncated,
                forwardStatus: email.forwardStatus,
                forwardTo: email.forwardTo,
                forwardError: email.forwardError,
                preview: email.text?.slice(0, PREVIEW_CHARS) ?? null,
            })),
        }
    },
})

/**
 * One archived email including its stored bodies.
 *
 * Takes `v.string()`, not `v.id()`, so an id that no longer exists returns
 * `null` instead of throwing (CLAUDE.md § Convex database access rules).
 */
export const get = query({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await requireAdmin(ctx, userId)

        const id = ctx.db.normalizeId('supportEmails', args.id)
        if (!id) return null
        return await ctx.db.get(id)
    },
})
