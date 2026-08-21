import {
    FEEDBACK_MAX_FILE_BYTES,
    FEEDBACK_MAX_FILES,
    FEEDBACK_MAX_TEXT_CHARS,
} from '@wallet-bot/shared'
import type { Id } from '../_generated/dataModel'
import type { MutationCtx } from '../_generated/server'

export { FEEDBACK_MAX_FILE_BYTES, FEEDBACK_MAX_FILES, FEEDBACK_MAX_TEXT_CHARS }

/**
 * Metadata Convex records for a stored file. `ctx.storage.getMetadata` is
 * deprecated, so the `_storage` system table is the supported way to read it
 * (`convex/_generated/ai/guidelines.md` § File storage guidelines).
 */
type StoredFile = {
    _id: Id<'_storage'>
    size: number
    contentType?: string
}

/** What the client claims it uploaded. Ids arrive as plain strings. */
export type ClaimedAttachment = {
    storageId: string
    filename: string | null
}

export type VerifiedAttachment = {
    storageId: Id<'_storage'>
    filename: string | null
    contentType: string | null
    size: number
}

/**
 * What `submit` refuses. Returned to the client as `{ ok: false, error }` so a
 * rejection is always visible; nothing is silently dropped.
 */
export type FeedbackRejection =
    | 'rate_limited'
    | 'empty'
    | 'text_too_long'
    | 'too_many_files'
    | 'file_too_large'
    | 'unknown_attachment'

/**
 * Resolves every claimed attachment against the `_storage` system table.
 *
 * The client hands over storage ids and filenames. Nothing about a file is
 * taken on trust: an id that is malformed or resolves to nothing is
 * `unknown_attachment`, and the size and content type written to the row are
 * the ones Convex actually recorded, never the client's claim. This is what
 * makes the per-file cap real rather than advisory — a short-lived upload URL
 * cannot police what gets sent to it.
 *
 * Ids are `v.string()` rather than `v.id('_storage')` deliberately: a client
 * may hand over an id that no longer exists, and `v.id()` would make that a
 * thrown validator error instead of the `unknown_attachment` verdict this
 * returns (CLAUDE.md § Convex database access rules).
 *
 * On any rejection every file in the batch is deleted, including the ones that
 * verified. A submission that never becomes a row must not leave bytes behind,
 * and keeping half a batch would be a slow storage leak with no row pointing
 * at it.
 */
export async function verifyAttachments(
    ctx: MutationCtx,
    claimed: readonly ClaimedAttachment[],
): Promise<
    | { ok: true; attachments: VerifiedAttachment[] }
    | { ok: false; error: FeedbackRejection }
> {
    // Normalized up front so cleanup on a later rejection can reach every file
    // in the batch, not just the ones checked before the failure.
    const resolved = claimed.map((file) => ({
        filename: file.filename,
        storageId: ctx.db.system.normalizeId('_storage', file.storageId),
    }))
    const real = resolved
        .map((file) => file.storageId)
        .filter((id): id is Id<'_storage'> => id !== null)

    const reject = async (error: FeedbackRejection) => {
        await discardFiles(ctx, real)
        return { ok: false as const, error }
    }

    if (claimed.length > FEEDBACK_MAX_FILES)
        return await reject('too_many_files')

    const attachments: VerifiedAttachment[] = []
    for (const file of resolved) {
        if (file.storageId === null) return await reject('unknown_attachment')

        const stored: StoredFile | null = await ctx.db.system.get(
            '_storage',
            file.storageId,
        )
        if (stored === null) return await reject('unknown_attachment')
        if (stored.size > FEEDBACK_MAX_FILE_BYTES) {
            return await reject('file_too_large')
        }

        attachments.push({
            storageId: file.storageId,
            filename: file.filename,
            contentType: stored.contentType ?? null,
            size: stored.size,
        })
    }

    return { ok: true, attachments }
}

/**
 * Deletes orphaned uploads. A file that is already gone is not an error here —
 * the goal is that nothing survives, and a no-op delete reaches that state just
 * as well.
 */
export async function discardFiles(
    ctx: MutationCtx,
    storageIds: readonly Id<'_storage'>[],
): Promise<void> {
    for (const storageId of storageIds) {
        try {
            await ctx.storage.delete(storageId)
        } catch {
            // Already deleted, or never really existed. Either way there is
            // nothing left to clean up and the caller's verdict still stands.
        }
    }
}
