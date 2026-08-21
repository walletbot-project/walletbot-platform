import {
    FEEDBACK_MAX_TEXT_CHARS,
    isSubmittableFeedback,
} from '@wallet-bot/shared'
import { v } from 'convex/values'
import { mutation } from '../../_generated/server'
import {
    type FeedbackRejection,
    verifyAttachments,
} from '../../feedback/helpers'
import { checkFeedbackLimit } from '../../feedback/rateLimits'
import { getOptionalUserId } from '../../users/helpers'

/**
 * In-app feedback ingress. Both functions here are **deliberately callable
 * without authentication**: a native local-only account has no backend user,
 * and CLAUDE.md's offline-first rule makes it a first-class account rather
 * than a degraded one. Authenticated callers (web, and native remote accounts)
 * are attributed; everyone else is recorded as anonymous.
 *
 * "Public" here means public to the internet, so both are rate limited on a
 * per-device key *and* a global backstop — see `feedback/rateLimits.ts` for why
 * the per-device key alone is not enough.
 *
 * Nothing about the caller is taken from the client: `userId` comes from
 * `ctx.auth`, and every attachment's size and content type are read back off
 * the `_storage` table. `platform`, `appVersion`, `deviceId` and `locale` are
 * stored as *claims* for triage and never authorize anything.
 */

/** Client identity, echoed onto the row for triage. Never authorizes. */
const clientArgs = {
    platform: v.string(),
    appVersion: v.string(),
    deviceId: v.union(v.string(), v.null()),
    locale: v.union(v.string(), v.null()),
}

/**
 * Step 1 of the upload: mint a short-lived URL the client POSTs bytes to.
 *
 * The bytes go straight to Convex storage and never pass through a Convex
 * function, so there is no 20 MB request cap the way there would be if this
 * were an HTTP action storing the blob itself. The per-file ceiling is instead
 * enforced in `submit`, which reads the stored size back — an upload URL
 * cannot police what is sent to it.
 *
 * A URL handed out here and never referenced by a `submit` call leaves an
 * orphaned file. That is the price of direct upload; the rate limits bound how
 * many such files a caller can create.
 */
export const generateUploadUrl = mutation({
    args: { deviceId: v.union(v.string(), v.null()) },
    handler: async (ctx, args) => {
        const limited = await checkFeedbackLimit(
            ctx,
            'uploadUrl',
            args.deviceId,
        )
        if (limited) {
            return {
                ok: false as const,
                error: 'rate_limited' as const,
                retryAfterMs: limited.retryAfterMs,
            }
        }
        return {
            ok: true as const,
            uploadUrl: await ctx.storage.generateUploadUrl(),
        }
    },
})

/**
 * Step 2: record the report and adopt the uploaded files.
 *
 * Returns `{ ok: false, error }` rather than throwing, matching the shape
 * `v1/sync` already uses, so each client can map a refusal onto its own copy
 * instead of parsing an exception message.
 */
export const submit = mutation({
    args: {
        text: v.string(),
        // `v.string()`, not `v.id('_storage')`: a client can hand over an id
        // that no longer exists, and that must come back as
        // `unknown_attachment` rather than a thrown validator error.
        attachments: v.array(
            v.object({
                storageId: v.string(),
                filename: v.union(v.string(), v.null()),
            }),
        ),
        ...clientArgs,
    },
    handler: async (ctx, args) => {
        const reject = (error: FeedbackRejection, retryAfterMs?: number) => ({
            ok: false as const,
            error,
            retryAfterMs: retryAfterMs ?? null,
        })

        const limited = await checkFeedbackLimit(ctx, 'submit', args.deviceId)
        if (limited) return reject('rate_limited', limited.retryAfterMs)

        const text = args.text.trim()
        if (
            !isSubmittableFeedback({
                text,
                attachmentCount: args.attachments.length,
            })
        ) {
            return reject('empty')
        }
        if (text.length > FEEDBACK_MAX_TEXT_CHARS)
            return reject('text_too_long')

        const verified = await verifyAttachments(ctx, args.attachments)
        if (!verified.ok) return reject(verified.error)

        // Resolved server-side. A local-only account has no identity at all and
        // is recorded as anonymous; the client never asserts who it is.
        const userId = await getOptionalUserId(ctx)

        await ctx.db.insert('feedback', {
            userId,
            text,
            attachments: verified.attachments,
            platform: args.platform,
            appVersion: args.appVersion,
            deviceId: args.deviceId,
            locale: args.locale,
            submittedAt: Date.now(),
        })

        return { ok: true as const }
    },
})
