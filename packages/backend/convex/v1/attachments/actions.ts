import { ATTACHMENT_MAX_QUESTION_LENGTH } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internal } from '../../_generated/api'
import { action } from '../../_generated/server'
import type { BeginReadResult } from '../../attachments/internal'
import {
    type AttachmentReadResult,
    readContextValidator,
    readFailure,
    sanitizeReadContext,
} from '../../attachments/utils'
import { getOptionalUserId } from '../../users/helpers'

/**
 * Executes the agent's `readAttachment` tool. Both clients call it from their
 * tool executor and forward the result to Gemini as-is: success carries the
 * reading, failure a model-facing `error` plus a `code` for the UI.
 *
 * Callable without authentication for native local accounts, which pass their
 * device id; a signed-in identity always wins over it.
 */
export const read = action({
    args: {
        attachmentId: v.string(),
        question: v.string(),
        deviceId: v.optional(v.string()),
        context: v.optional(readContextValidator),
    },
    handler: async (ctx, args): Promise<AttachmentReadResult> => {
        const question = args.question.trim()
        if (!question || question.length > ATTACHMENT_MAX_QUESTION_LENGTH) {
            return readFailure('question_invalid')
        }

        const userId = await getOptionalUserId(ctx)
        const gate: BeginReadResult = await ctx.runMutation(
            internal.attachments.internal.beginRead,
            {
                userId: userId ?? undefined,
                deviceId: args.deviceId,
                attachmentId: args.attachmentId,
            },
        )
        if (!gate.ok) return readFailure(gate.code, gate.retryAfter)

        const result: AttachmentReadResult = await ctx.runAction(
            internal.attachments.nodeActions.readWithModel,
            {
                ...gate.attachment,
                question,
                context: sanitizeReadContext(args.context),
            },
        )
        return result
    },
})
