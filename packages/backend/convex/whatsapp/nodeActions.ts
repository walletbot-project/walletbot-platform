'use node'

import { v } from 'convex/values'
import { internal } from '../_generated/api'
import type { Id } from '../_generated/dataModel'
import type { ActionCtx } from '../_generated/server'
import { internalAction } from '../_generated/server'
import { chunkBody, sendText, windowIsOpen } from './helpers'
import {
    extractLinkCodeCandidates,
    linkReplyText,
    replyLanguageFor,
} from './linking'

// A Node action so the real agent can use @google/genai, the same way
// live/createToken.ts does. Everything it imports (helpers.ts) is plain fetch,
// which the import-chain rule in CLAUDE.md requires.

// Safety valve on the drain loop. Convex actions have an execution limit, so a
// conversation busy enough to keep producing work hands off to a fresh action
// rather than looping until it is killed mid-turn.
const MAX_LOOPS = 20

type ClaimedMessage = {
    type: string
    text: string | null
    mediaId: string | null
    sentAt: number
}

// Sends one reply, splitting it if WhatsApp's 4096-character limit demands, and
// logs every part to the outbound table. Stops at the first failure: the parts
// are ordered prose, so delivering part 3 without part 2 is worse than
// stopping.
const sendReply = async (
    ctx: ActionCtx,
    args: {
        conversationId: Id<'whatsappConversations'>
        phoneNumberId: string
        waId: string
        body: string
    },
): Promise<void> => {
    for (const chunk of chunkBody(args.body)) {
        const result = await sendText({
            phoneNumberId: args.phoneNumberId,
            to: args.waId,
            body: chunk,
        })
        await ctx.runMutation(internal.whatsapp.internal.recordOutbound, {
            conversationId: args.conversationId,
            text: chunk,
            wamid: result.ok ? result.wamid : undefined,
            status: result.ok ? 'sent' : 'failed',
            errorCode: result.ok ? undefined : result.errorCode,
            errorMessage: result.ok ? undefined : result.errorMessage,
        })
        if (!result.ok) {
            console.error(
                `whatsapp send to ${args.waId} failed (${result.errorCode ?? 'no code'}): ${result.errorMessage}`,
            )
            return
        }
    }
}

// The only thing an unidentified sender can do.
//
// No model, no tools, no account data — a conversation with no userId has not
// proven anything, and the webhook that fed it is public. Everything this
// branch can do is compare the text against the pending link codes and answer
// with fixed copy.
//
// Codes are gathered across the whole batch because the user may have sent
// "hola" and the code as two separate messages, which coalesce into one turn.
const resolveLink = async (
    ctx: ActionCtx,
    args: {
        conversationId: Id<'whatsappConversations'>
        runId: string
        waId: string
        messages: ClaimedMessage[]
    },
): Promise<{ fenced: true } | { fenced: false; reply: string | null }> => {
    const candidates: string[] = []
    for (const message of args.messages) {
        if (message.text === null) continue
        for (const candidate of extractLinkCodeCandidates(message.text)) {
            if (!candidates.includes(candidate)) candidates.push(candidate)
        }
    }

    const outcome = await ctx.runMutation(internal.whatsapp.internal.tryLink, {
        conversationId: args.conversationId,
        runId: args.runId,
        candidates,
    })
    if (outcome.kind === 'fenced') return { fenced: true }
    if (outcome.kind === 'linked') {
        console.info(
            `whatsapp conversation ${args.conversationId} linked to a Wallet Bot account`,
        )
    }
    // Language comes from the sender's country code: there is no account yet,
    // so no stored locale to read.
    return {
        fenced: false,
        reply: linkReplyText(outcome, replyLanguageFor(args.waId)),
    }
}

// TODO(agent): replace with the real agent. Deliberately a stub so the
// concurrency can be tested before the LLM is in the picture — send three
// messages in quick succession and you should get exactly one reply listing all
// three, which is the coalescing behaviour working.
const generateReply = async (batch: {
    userId: string
    messages: ClaimedMessage[]
}): Promise<string> => {
    const lines = batch.messages.map((message, index) => {
        const body =
            message.text ??
            `<${message.type}${message.mediaId ? ` ${message.mediaId}` : ''}>`
        return `${index + 1}. ${body}`
    })
    return `Recibí ${batch.messages.length} mensaje(s) en este turno:\n${lines.join('\n')}`
}

// Drains a conversation's queue until it is empty, then releases the lock.
//
// The loop is the point: messages that arrive while the agent is generating are
// picked up on the next iteration and folded into the following turn, so a user
// typing several fragments gets one considered reply instead of a reply per
// fragment. Exiting is decided by `claimOrRelease` inside a single transaction —
// see the race note there.
export const runAgentTurn = internalAction({
    args: {
        conversationId: v.id('whatsappConversations'),
        runId: v.string(),
    },
    handler: async (ctx, { conversationId, runId }) => {
        for (let loop = 0; loop < MAX_LOOPS; loop += 1) {
            const claim = await ctx.runMutation(
                internal.whatsapp.internal.claimOrRelease,
                { conversationId, runId },
            )

            // Someone else owns this conversation now (the reaper released our
            // lock and a newer turn took it). Stop touching shared state.
            if (claim.kind === 'fenced') return null
            // Queue drained and the lock is already back to idle.
            if (claim.kind === 'released') return null

            const messageIds = claim.messages.map((message) => message.id)

            try {
                // Checked before generating so we don't pay for an LLM call we
                // cannot deliver. Meta would accept the send and drop it
                // silently, which is worse than not sending.
                if (!windowIsOpen(claim.windowExpiresAt)) {
                    console.error(
                        `whatsapp conversation ${conversationId} (${claim.waId}) is outside its 24h window; cannot send free-form. An approved template is required.`,
                    )
                    await ctx.runMutation(
                        internal.whatsapp.internal.finishBatch,
                        {
                            messageIds,
                            status: 'failed',
                            failureReason: 'service_window_closed',
                        },
                    )
                    continue
                }

                // Identity gate. An unlinked conversation never reaches the
                // model or a tool — it only gets the link flow.
                if (claim.userId === null) {
                    const link = await resolveLink(ctx, {
                        conversationId,
                        runId,
                        waId: claim.waId,
                        messages: claim.messages,
                    })
                    if (link.fenced) return null
                    if (link.reply !== null) {
                        await sendReply(ctx, {
                            conversationId,
                            phoneNumberId: claim.phoneNumberId,
                            waId: claim.waId,
                            body: link.reply,
                        })
                    }
                    await ctx.runMutation(
                        internal.whatsapp.internal.finishBatch,
                        { messageIds, status: 'processed' },
                    )
                    continue
                }

                const reply = await generateReply({
                    userId: claim.userId,
                    messages: claim.messages,
                })

                await sendReply(ctx, {
                    conversationId,
                    phoneNumberId: claim.phoneNumberId,
                    waId: claim.waId,
                    body: reply,
                })

                await ctx.runMutation(internal.whatsapp.internal.finishBatch, {
                    messageIds,
                    status: 'processed',
                })
            } catch (error) {
                // Never leave the batch claimed: a claimed row is invisible to
                // the next turn, so the user's message would vanish.
                console.error(
                    `whatsapp agent turn failed for ${conversationId}: ${String(error)}`,
                )
                await ctx.runMutation(internal.whatsapp.internal.finishBatch, {
                    messageIds,
                    status: 'failed',
                    failureReason: String(error),
                })
            }
        }

        // Still busy after MAX_LOOPS. Hand the lock to a fresh action instead of
        // risking being killed mid-turn while still holding it.
        console.warn(
            `whatsapp conversation ${conversationId} still busy after ${MAX_LOOPS} loops; handing off`,
        )
        await ctx.runMutation(internal.whatsapp.internal.handOffTurn, {
            conversationId,
            runId,
        })
        return null
    },
})
