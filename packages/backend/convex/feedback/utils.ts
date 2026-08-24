import {
    FEEDBACK_MAX_ATTACHMENT_BYTES,
    FEEDBACK_MAX_ATTACHMENTS,
    FEEDBACK_MAX_MESSAGE_LENGTH,
} from '@wallet-bot/shared'

export {
    FEEDBACK_MAX_ATTACHMENT_BYTES,
    FEEDBACK_MAX_ATTACHMENTS,
    FEEDBACK_MAX_MESSAGE_LENGTH,
}

/**
 * Cap on the client-supplied device id used to key the anonymous rate limit.
 * `ClientInfo.deviceId` is a uuid; anything longer is a client bug or an attempt
 * to bloat the rate-limiter's key space.
 */
export const MAX_DEVICE_ID_LENGTH = 128

/** Cap on a stored attachment file name. */
export const MAX_ATTACHMENT_NAME_LENGTH = 256

/**
 * How long an uploaded-but-unsubmitted file is kept before the cleanup cron
 * reclaims it. Generous enough that a slow multi-file submission in progress is
 * never touched.
 */
export const ORPHAN_ATTACHMENT_TTL_MS = 24 * 60 * 60 * 1000

/** Why a submission was rejected. Mirrored in both clients' copy. */
export type FeedbackError =
    | 'rate_limited'
    | 'unidentified_client'
    | 'message_invalid'
    | 'attachment_invalid'

export type FeedbackResult =
    | { ok: true }
    | { ok: false; error: FeedbackError; retryAfter?: number }

export type UploadUrlResult =
    | { ok: true; uploadUrl: string }
    | { ok: false; error: FeedbackError; retryAfter?: number }
