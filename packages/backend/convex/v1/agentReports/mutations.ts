import { isAgentReportStatus } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { mutation } from '../../_generated/server'
import { consumeAgentReportLimit } from '../../agentReports/helpers'
import {
    type AgentReportResult,
    MAX_REVIEW_NOTE_LENGTH,
    normalizeReport,
} from '../../agentReports/utils'
import { requireAdmin } from '../../featureFlags/helpers'
import { resolveSubmitter } from '../../feedback/helpers'
import { recordAgentReportSubmitted } from '../../telemetry/metrics'
import { requireAuth } from '../../users/helpers'

/**
 * V1 agent-response reporting contract.
 *
 * Deliberately callable WITHOUT authentication, for the same reason
 * `v1/feedback/mutations` is: native local-only accounts have no backend user,
 * and they must still be able to flag a response. An unauthenticated caller
 * identifies itself with `deviceId` and gets the tighter limit in
 * `agentReports/rateLimits.ts`; a signed-in caller's identity always wins over
 * any `deviceId` it also sends.
 */

export const submit = mutation({
    args: {
        reason: v.string(),
        scope: v.string(),
        note: v.optional(v.string()),
        reportedText: v.optional(v.string()),
        precedingUserText: v.optional(v.string()),
        sessionId: v.optional(v.string()),
        model: v.optional(v.string()),
        occurredAt: v.optional(v.int64()),
        platform: v.string(),
        appVersion: v.optional(v.string()),
        locale: v.optional(v.string()),
        /** Required when the caller has no identity (native local account). */
        deviceId: v.optional(v.string()),
    },
    handler: async (ctx, args): Promise<AgentReportResult> => {
        const submitter = await resolveSubmitter(ctx, args.deviceId)
        if (!submitter) return { ok: false, error: 'unidentified_client' }

        // Validated BEFORE the limit is consumed, matching feedback's ordering:
        // a rejected report writes nothing, so charging a token for it would
        // only cost a real reporter one of their few daily attempts.
        const report = normalizeReport(args)
        if (!report.ok) return { ok: false, error: report.error }

        const limit = await consumeAgentReportLimit(ctx, submitter)
        if (!limit.ok) {
            return {
                ok: false,
                error: 'rate_limited',
                retryAfter: limit.retryAfter,
            }
        }

        await ctx.db.insert('agentReports', {
            ...report.value,
            ...(args.model ? { model: args.model } : {}),
            ...(args.occurredAt !== undefined
                ? { occurredAt: args.occurredAt }
                : {}),
            ...(submitter.kind === 'user'
                ? { userId: submitter.userId }
                : { deviceId: submitter.deviceId }),
            platform: args.platform,
            appVersion: args.appVersion,
            locale: args.locale,
            status: 'pending',
            createdAt: BigInt(Date.now()),
        })

        await recordAgentReportSubmitted(ctx, {
            ...(submitter.kind === 'user' ? { userId: submitter.userId } : {}),
            reason: report.value.reason,
            scope: report.value.scope,
            clientPlatform: args.platform,
        })

        return { ok: true }
    },
})

/**
 * Moves a report through the queue. Admin-only — the row holds a slice of
 * someone's conversation.
 */
export const review = mutation({
    args: {
        reportId: v.id('agentReports'),
        status: v.string(),
        reviewNote: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        await requireAdmin(ctx, userId)

        if (!isAgentReportStatus(args.status)) {
            throw new Error(`Unknown agent report status: ${args.status}`)
        }

        const report = await ctx.db.get(args.reportId)
        if (!report) throw new Error('Agent report not found')

        const reviewNote = args.reviewNote
            ?.trim()
            .slice(0, MAX_REVIEW_NOTE_LENGTH)

        await ctx.db.patch(args.reportId, {
            status: args.status,
            reviewedBy: userId,
            reviewedAt: BigInt(Date.now()),
            reviewNote: reviewNote || undefined,
        })

        return { ok: true }
    },
})
