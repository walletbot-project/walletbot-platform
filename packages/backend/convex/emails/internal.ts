import { vOnEmailEventArgs } from '@convex-dev/resend'
import { components } from '../_generated/api'
import { internalMutation } from '../_generated/server'

// sendEmail only confirms the email was queued — a bad API key, unverified
// domain, or bouncing recipient surfaces asynchronously, through Resend's
// webhook (requires RESEND_WEBHOOK_SECRET + a webhook in the Resend
// dashboard pointing at /resend-webhook). This handler is the only place
// those delivery failures ever become visible.
export const handleEmailEvent = internalMutation({
    args: vOnEmailEventArgs,
    handler: async (_ctx, { id, event }) => {
        switch (event.type) {
            case 'email.bounced':
                console.error(
                    `email ${id} to ${[event.data.to].flat().join(', ')} bounced (${event.data.bounce.type}): ${event.data.bounce.message}`,
                )
                break
            case 'email.failed':
                console.error(
                    `email ${id} to ${[event.data.to].flat().join(', ')} failed: ${event.data.failed.reason}`,
                )
                break
            case 'email.complained':
                console.error(
                    `email ${id} to ${[event.data.to].flat().join(', ')} marked as spam`,
                )
                break
            default:
                console.log(`email ${id}: ${event.type}`)
        }
        return null
    },
})

const DAY_MS = 24 * 60 * 60 * 1000

// Prunes the resend component's finalized/abandoned email rows so the
// tables don't grow unbounded. Scheduled daily from crons.ts.
export const cleanupResendEmails = internalMutation({
    args: {},
    handler: async (ctx) => {
        await ctx.scheduler.runAfter(
            0,
            components.resend.lib.cleanupOldEmails,
            {
                olderThan: 7 * DAY_MS,
            },
        )
        await ctx.scheduler.runAfter(
            0,
            components.resend.lib.cleanupAbandonedEmails,
            { olderThan: 30 * DAY_MS },
        )
        return null
    },
})
