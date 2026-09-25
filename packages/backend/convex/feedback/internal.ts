import { v } from 'convex/values'
import { internalMutation } from '../_generated/server'

/**
 * Reclaims files that were uploaded but never attached to a submission.
 *
 * A client asks for an upload URL and POSTs the bytes before it calls `submit`,
 * so every abandoned sheet — and every rejected submission — leaves stored bytes
 * behind, up to 1 GB per attempt. Agent chat attachments follow the same
 * upload-then-register flow. Those are the only two things that store files, so
 * "in `_storage` but referenced by no `feedbackAttachments` or
 * `agentAttachments` row" is exactly the set of garbage. An attachment's own
 * file is deleted with it on expiry (`attachments/internal.ts`).
 *
 * Walks `_storage` oldest-first in `limit`-sized windows, never a full scan, and
 * only ever looks at files older than `olderThanMs` so an upload belonging to a
 * submission still in flight is out of reach. The frontier it advances
 * (`feedbackSweepState`) is what keeps the window moving: referenced files are
 * permanent, and without a frontier they would eventually fill every window.
 */
export const deleteOrphanAttachments = internalMutation({
    args: { olderThanMs: v.number(), limit: v.number() },
    handler: async (ctx, args) => {
        const cutoff = Date.now() - args.olderThanMs
        // Single-row table by construction — written only below.
        const state = await ctx.db.query('feedbackSweepState').first()
        const from = state?.lastCreationTime ?? 0

        const files = await ctx.db.system
            .query('_storage')
            .withIndex('by_creation_time', (q) =>
                q.gt('_creationTime', from).lte('_creationTime', cutoff),
            )
            .order('asc')
            .take(args.limit)

        let deleted = 0
        for (const file of files) {
            const reference =
                (await ctx.db
                    .query('feedbackAttachments')
                    .withIndex('by_storageId', (q) =>
                        q.eq('storageId', file._id),
                    )
                    .first()) ??
                (await ctx.db
                    .query('agentAttachments')
                    .withIndex('by_storageId', (q) =>
                        q.eq('storageId', file._id),
                    )
                    .first())
            if (reference) continue
            await ctx.storage.delete(file._id)
            deleted += 1
        }

        const last = files.at(-1)
        if (last) {
            if (state) {
                await ctx.db.patch(state._id, {
                    lastCreationTime: last._creationTime,
                })
            } else {
                await ctx.db.insert('feedbackSweepState', {
                    lastCreationTime: last._creationTime,
                })
            }
        }

        return { inspected: files.length, deleted }
    },
})
