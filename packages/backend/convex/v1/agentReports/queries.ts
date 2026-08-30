import { isAgentReportStatus } from '@wallet-bot/shared'
import { paginationOptsValidator } from 'convex/server'
import { v } from 'convex/values'
import { query } from '../../_generated/server'
import { requireAdmin } from '../../featureFlags/helpers'
import { requireAuth } from '../../users/helpers'

/**
 * The moderation queue's read path, admin-only. Always paginated over
 * `by_status_and_createdAt`: the table grows without bound and a report is
 * triaged oldest-first within a status.
 */
export const list = query({
    args: { status: v.string(), paginationOpts: paginationOptsValidator },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await requireAdmin(ctx, userId)

        if (!isAgentReportStatus(args.status)) {
            throw new Error(`Unknown agent report status: ${args.status}`)
        }

        const result = await ctx.db
            .query('agentReports')
            .withIndex('by_status_and_createdAt', (q) =>
                q.eq('status', args.status),
            )
            .order('asc')
            .paginate(args.paginationOpts)

        return {
            ...result,
            page: result.page.map((report) => ({
                id: report._id,
                reason: report.reason,
                scope: report.scope,
                note: report.note,
                reportedText: report.reportedText,
                precedingUserText: report.precedingUserText,
                sessionId: report.sessionId,
                model: report.model,
                occurredAt: report.occurredAt,
                // Whether the reporter was signed in, not who they were: the
                // queue is about the response, and an email would put an
                // identity next to conversation text for no moderation gain.
                reporter: report.userId ? 'account' : 'device',
                platform: report.platform,
                appVersion: report.appVersion,
                locale: report.locale,
                status: report.status,
                reviewNote: report.reviewNote,
                reviewedAt: report.reviewedAt,
                createdAt: report.createdAt,
            })),
        }
    },
})

/** Pending count for the queue's badge. Bounded read, never a full scan. */
export const pendingCount = query({
    args: { limit: v.number() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await requireAdmin(ctx, userId)

        const capped = Math.min(Math.max(args.limit, 1), 100)
        const rows = await ctx.db
            .query('agentReports')
            .withIndex('by_status_and_createdAt', (q) =>
                q.eq('status', 'pending'),
            )
            .take(capped)
        return { count: rows.length, capped: rows.length === capped }
    },
})
