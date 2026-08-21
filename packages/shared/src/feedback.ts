/**
 * In-app feedback contract, shared by the backend validators and both
 * clients' pickers.
 *
 * The caps are declared once here because they are enforced in three places
 * and must agree: each client refuses to attach a file that violates them
 * (so the user learns before spending an upload), and
 * `v1/feedback/mutations:submit` re-reads `_storage` metadata to check them
 * again server-side. A client is never trusted about a file's size — the
 * client-side check is a courtesy, the server-side one is the rule.
 */

/** Attachments allowed per submission. */
export const FEEDBACK_MAX_FILES = 5

/**
 * Per-file ceiling. Uploads go through a short-lived Convex upload URL, which
 * has no request-size limit of its own (unlike an HTTP action's 20 MB cap), so
 * this number is a product decision rather than a platform one.
 */
export const FEEDBACK_MAX_FILE_BYTES = 25 * 1024 * 1024

/**
 * Written-report ceiling. Long enough for a detailed bug report, short enough
 * that a page of rows stays well inside Convex's query result limit.
 */
export const FEEDBACK_MAX_TEXT_CHARS = 4000

/** Human-readable per-file cap, for the pickers' helper copy. */
export const FEEDBACK_MAX_FILE_MB = FEEDBACK_MAX_FILE_BYTES / (1024 * 1024)

/**
 * A submission needs *something* in it. Attachments alone are a valid report
 * — a screenshot of a broken screen says plenty — so this only rejects the
 * completely empty case.
 */
export const isSubmittableFeedback = (args: {
    text: string
    attachmentCount: number
}): boolean => args.text.trim().length > 0 || args.attachmentCount > 0
