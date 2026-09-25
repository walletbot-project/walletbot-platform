import { defineTable } from 'convex/server'
import { v } from 'convex/values'

/**
 * Files attached to the agent chat, readable through the `readAttachment` tool
 * until `expiresAt`. Owned by EITHER a signed-in `userId` or a native local
 * account's `deviceId`, never both, like `feedback`.
 *
 * `size` and `contentType` come from the `_storage` metadata the server read,
 * never from the client. `by_storageId` lets the orphan sweep
 * (`feedback/internal.ts`) tell an attachment's file from garbage.
 */
export const agentAttachments = defineTable({
    userId: v.optional(v.string()),
    deviceId: v.optional(v.string()),
    storageId: v.id('_storage'),
    /** The client-supplied file name, shown to the model for context only. */
    name: v.string(),
    kind: v.union(
        v.literal('image'),
        v.literal('pdf'),
        v.literal('document'),
        v.literal('spreadsheet'),
        v.literal('text'),
    ),
    contentType: v.string(),
    size: v.number(),
    expiresAt: v.number(),
})
    .index('by_storageId', ['storageId'])
    .index('by_expiresAt', ['expiresAt'])
    .index('by_userId', ['userId'])
