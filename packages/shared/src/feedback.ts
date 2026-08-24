/**
 * In-app feedback limits, shared by the clients' pre-checks and the server's
 * enforcement so the two can't drift.
 *
 * The client checks are UX only: a file goes straight from the browser/device to
 * a Convex upload URL, so the server first sees it as `_storage` metadata and
 * enforces the size there (`v1/feedback/mutations.ts`).
 */

/** Attachments allowed on a single submission. */
export const FEEDBACK_MAX_ATTACHMENTS = 10

/** Largest single attachment, in bytes (100 MB). */
export const FEEDBACK_MAX_ATTACHMENT_BYTES = 100 * 1024 * 1024

/** Longest feedback message, in characters. */
export const FEEDBACK_MAX_MESSAGE_LENGTH = 4000
