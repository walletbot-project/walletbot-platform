import { v } from 'convex/values'
import type { Id } from '../_generated/dataModel'
import { internalMutation } from '../_generated/server'
import { supportEmailAttachment } from '../schema/supportEmails'

/**
 * Archives one inbound support email, or reports that it is already archived.
 *
 * Called *before* the forward is attempted (`support/actions.ts`) so a Resend
 * outage on the forwarding leg still leaves the message stored — the row lands
 * with `forwardStatus: 'pending'` and `markForwardResult` settles it.
 *
 * Idempotent by `resendEmailId`: Resend retries a webhook until it gets a 2xx,
 * and the caller uses `alreadyStored` to skip re-forwarding a message the
 * support inbox has already received. Two concurrent retries can both read
 * before either writes, but Convex mutations are serializable — the loser
 * re-runs and then sees the winner's row.
 */
export const recordInboundEmail = internalMutation({
    args: {
        resendEmailId: v.string(),
        from: v.string(),
        to: v.array(v.string()),
        cc: v.array(v.string()),
        bcc: v.array(v.string()),
        replyTo: v.array(v.string()),
        receivedFor: v.array(v.string()),
        subject: v.string(),
        messageId: v.string(),
        html: v.union(v.string(), v.null()),
        text: v.union(v.string(), v.null()),
        bodyTruncated: v.boolean(),
        attachments: v.array(supportEmailAttachment),
        receivedAt: v.number(),
    },
    returns: v.object({
        id: v.id('supportEmails'),
        alreadyStored: v.boolean(),
    }),
    handler: async (
        ctx,
        args,
    ): Promise<{ id: Id<'supportEmails'>; alreadyStored: boolean }> => {
        const existing = await ctx.db
            .query('supportEmails')
            .withIndex('by_resendEmailId', (q) =>
                q.eq('resendEmailId', args.resendEmailId),
            )
            .unique()
        if (existing) {
            return { id: existing._id, alreadyStored: true }
        }

        const id = await ctx.db.insert('supportEmails', {
            ...args,
            storedAt: Date.now(),
            forwardStatus: 'pending',
            forwardTo: null,
            forwardResendEmailId: null,
            forwardError: null,
            forwardedAt: null,
        })
        return { id, alreadyStored: false }
    },
})

/**
 * Settles the forwarding leg of an already-archived email.
 *
 * A `failed` row is the only record that someone wrote in and the support
 * inbox never got it, so the error message is kept on the row rather than only
 * in the logs.
 */
export const markForwardResult = internalMutation({
    args: {
        id: v.id('supportEmails'),
        status: v.union(
            v.literal('sent'),
            v.literal('skipped'),
            v.literal('failed'),
        ),
        forwardTo: v.union(v.string(), v.null()),
        forwardResendEmailId: v.union(v.string(), v.null()),
        forwardError: v.union(v.string(), v.null()),
    },
    returns: v.null(),
    handler: async (ctx, args): Promise<null> => {
        const email = await ctx.db.get(args.id)
        if (!email) {
            console.error(
                `support email ${args.id} disappeared before its forward result could be recorded`,
            )
            return null
        }
        await ctx.db.patch(args.id, {
            forwardStatus: args.status,
            forwardTo: args.forwardTo,
            forwardResendEmailId: args.forwardResendEmailId,
            forwardError: args.forwardError,
            forwardedAt: Date.now(),
        })
        return null
    },
})
