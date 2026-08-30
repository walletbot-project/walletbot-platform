'use node'

import { v } from 'convex/values'
import { internal } from '../_generated/api'
import type { Id } from '../_generated/dataModel'
import type { ActionCtx } from '../_generated/server'
import { internalAction } from '../_generated/server'
import { turnKeyFor } from '../agent/idempotency'
import { runAgent } from '../agent/runner'
import { chunkBody, sendText, windowIsOpen } from './helpers'
import {
    disabledReplyText,
    extractLinkCodeCandidates,
    linkReplyText,
    replyLanguageFor,
    utcOffsetMinutesFor,
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

// The batch as one user turn.
//
// Messages that coalesced into this turn are joined rather than sent as
// separate turns: the user typed "gasté 5000" and "en el super" as two
// bubbles, but they are one thought and the model should read them that way.
//
// Non-text messages (audio, images, documents) are not downloaded — the media
// pipeline does not exist yet — so they are described rather than dropped,
// which lets the model say it cannot open them instead of ignoring the user.
const batchToPrompt = (messages: ClaimedMessage[]): string =>
    messages
        .map((message) => {
            if (message.text !== null && message.text.trim().length > 0) {
                return message.text.trim()
            }
            return `[the user sent a ${message.type} message, which I cannot open yet]`
        })
        .join('\n')

// Deliberately vague about *what* failed and non-committal about whether
// anything was saved: after an exception mid-turn we genuinely do not know,
// and telling the user "no se guardó" when it did would be worse than saying
// nothing precise. Pointing at the app gives them a way to check.
const failureReplyText = (language: 'es' | 'en'): string =>
    language === 'es'
        ? 'Tuve un problema procesando eso. Revisá en la app si quedó registrado antes de volver a mandarlo.'
        : 'Something went wrong handling that. Check the app to see whether it was saved before sending it again.'

// Runs the agent for one claimed batch and returns what to send back.
const generateReply = async (
    ctx: ActionCtx,
    args: {
        conversationId: Id<'whatsappConversations'>
        userId: string
        waId: string
        messages: ClaimedMessage[]
        messageIds: Id<'whatsappInboundMessages'>[]
    },
): Promise<string> => {
    const history = await ctx.runQuery(
        internal.whatsapp.internal.recentHistory,
        { conversationId: args.conversationId },
    )

    const result = await runAgent(ctx, {
        userId: args.userId,
        messages: [
            ...history,
            { role: 'user' as const, text: batchToPrompt(args.messages) },
        ],
        // The claimed rows' ids. If this turn dies before `finishBatch` and
        // the reaper re-queues them, the replay claims those same rows and
        // therefore rebuilds the same key — which is what stops the retry from
        // recording the user's expense a second time (R-039).
        turnKey: turnKeyFor(args.messageIds),
        nowMs: Date.now(),
        // Both inferred from the sender's country code, because a WhatsApp
        // conversation carries no locale of its own. The language is only the
        // fallback — `runAgent` prefers the language the account reported from
        // the app (R-046 still stands for the offset, which nothing reports).
        utcOffsetMinutes: utcOffsetMinutesFor(args.waId),
        preferredLanguage: replyLanguageFor(args.waId),
    })
    console.info(
        `whatsapp agent turn for ${args.conversationId}: ${result.rounds} round(s), ${result.toolCalls} tool call(s)`,
    )
    return result.text
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

                // Rollout gate, checked after identity and before the model.
                // A number linked while the flag was on keeps its link — and
                // its way to disconnect, in the app — but hears one fixed line
                // instead of an agent it is no longer entitled to.
                const enabled = await ctx.runQuery(
                    internal.whatsapp.internal.isEnabledForUser,
                    { userId: claim.userId },
                )
                if (!enabled) {
                    await sendReply(ctx, {
                        conversationId,
                        phoneNumberId: claim.phoneNumberId,
                        waId: claim.waId,
                        body: disabledReplyText(replyLanguageFor(claim.waId)),
                    })
                    await ctx.runMutation(
                        internal.whatsapp.internal.finishBatch,
                        { messageIds, status: 'processed' },
                    )
                    continue
                }

                const reply = await generateReply(ctx, {
                    conversationId,
                    userId: claim.userId,
                    waId: claim.waId,
                    messages: claim.messages,
                    messageIds,
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
                // Say something. A failed turn that stays silent is
                // indistinguishable from a bot that is ignoring you, and the
                // user's only recourse would be to send the message again —
                // which, on a turn that already half-succeeded, is the worst
                // thing they could do. Best effort: a send that also fails is
                // already logged by `sendReply`, and must not mask the error
                // above.
                try {
                    await sendReply(ctx, {
                        conversationId,
                        phoneNumberId: claim.phoneNumberId,
                        waId: claim.waId,
                        body: failureReplyText(replyLanguageFor(claim.waId)),
                    })
                } catch (sendError) {
                    console.error(
                        `whatsapp failure notice could not be sent to ${claim.waId}: ${String(sendError)}`,
                    )
                }
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
