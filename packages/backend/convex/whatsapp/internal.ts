import { v } from 'convex/values'
import { internal } from '../_generated/api'
import type { Doc, Id } from '../_generated/dataModel'
import { internalMutation, type MutationCtx } from '../_generated/server'
import type { ParsedInboundMessage } from './utils'

const WINDOW_MS = 24 * 60 * 60 * 1000

// A turn holding the lock longer than this is presumed dead — the action
// crashed, threw outside our try, or hit its execution limit. The reaper
// force-releases it; the `runId` fence stops the zombie from interfering if it
// ever resumes.
const STUCK_AFTER_MS = 5 * 60 * 1000

// Cap on messages claimed per turn. A mutation is a transaction with document
// read/write limits, so an unbounded claim could blow them if someone floods
// the number. Anything above the cap is simply picked up by the next loop
// iteration, so nothing is lost.
const MAX_BATCH = 50

// How many conversations the reaper repairs per run.
const REAPER_LIMIT = 25

const findConversation = async (
    ctx: MutationCtx,
    waId: string,
    phoneNumberId: string,
): Promise<Doc<'whatsappConversations'> | null> =>
    await ctx.db
        .query('whatsappConversations')
        .withIndex('by_waId_and_phoneNumberId', (q) =>
            q.eq('waId', waId).eq('phoneNumberId', phoneNumberId),
        )
        .unique()

const getOrCreateConversation = async (
    ctx: MutationCtx,
    message: ParsedInboundMessage,
    now: number,
): Promise<Id<'whatsappConversations'>> => {
    const existing = await findConversation(
        ctx,
        message.waId,
        message.phoneNumberId,
    )
    if (existing) return existing._id
    return await ctx.db.insert('whatsappConversations', {
        waId: message.waId,
        phoneNumberId: message.phoneNumberId,
        status: 'idle',
        lastInboundAt: now,
        windowExpiresAt: now + WINDOW_MS,
        createdAt: now,
    })
}

// Starts a turn only when none is running. This single check is what coalesces:
// if a turn is already in flight it will drain whatever we just inserted on its
// next loop, so a burst of messages produces one agent turn rather than one per
// message. Safe against concurrent webhooks because Convex mutations are
// serializable transactions — two callers cannot both observe `idle`.
const maybeStartTurn = async (
    ctx: MutationCtx,
    conversationId: Id<'whatsappConversations'>,
): Promise<void> => {
    const conversation = await ctx.db.get(conversationId)
    if (!conversation || conversation.status === 'processing') return
    const runId = crypto.randomUUID()
    await ctx.db.patch(conversationId, {
        status: 'processing',
        runId,
        processingStartedAt: Date.now(),
    })
    await ctx.scheduler.runAfter(
        0,
        internal.whatsapp.nodeActions.runAgentTurn,
        { conversationId, runId },
    )
}

const inboundMessageArgs = v.object({
    wamid: v.string(),
    waId: v.string(),
    phoneNumberId: v.string(),
    type: v.string(),
    text: v.optional(v.string()),
    mediaId: v.optional(v.string()),
    sentAt: v.number(),
})

// Called by the webhook, once per delivery. Must stay cheap: the HTTP handler
// has to ack Meta fast, so this only writes rows and schedules — never the LLM.
export const enqueueInbound = internalMutation({
    args: { messages: v.array(inboundMessageArgs) },
    handler: async (ctx, { messages }) => {
        const now = Date.now()
        const touched = new Set<Id<'whatsappConversations'>>()

        for (const message of messages) {
            // Meta retries webhook deliveries, so the same wamid arrives more
            // than once. Deduping here — not in the agent — keeps every
            // downstream stage able to assume each message is unique.
            const duplicate = await ctx.db
                .query('whatsappInboundMessages')
                .withIndex('by_wamid', (q) => q.eq('wamid', message.wamid))
                .first()
            if (duplicate) continue

            const conversationId = await getOrCreateConversation(
                ctx,
                message,
                now,
            )
            await ctx.db.insert('whatsappInboundMessages', {
                conversationId,
                wamid: message.wamid,
                waId: message.waId,
                type: message.type,
                text: message.text,
                mediaId: message.mediaId,
                sentAt: message.sentAt,
                receivedAt: now,
                status: 'pending',
            })
            // Every inbound message re-opens the 24h service window.
            await ctx.db.patch(conversationId, {
                lastInboundAt: now,
                windowExpiresAt: now + WINDOW_MS,
            })
            touched.add(conversationId)
        }

        // One wake-up per conversation, after all inserts — not per message.
        for (const conversationId of touched) {
            await maybeStartTurn(ctx, conversationId)
        }
        return null
    },
})

// Claims the pending batch, or releases the lock if there is nothing left.
//
// These are one mutation on purpose. Splitting them would reopen the classic
// lost-wakeup race: a message arriving between "queue looks empty" and "set
// idle" would find the conversation still `processing`, decline to start a
// turn, and then sit there forever because the turn that would have drained it
// has already exited. Deciding both inside one transaction makes that window
// nonexistent.
export const claimOrRelease = internalMutation({
    args: {
        conversationId: v.id('whatsappConversations'),
        runId: v.string(),
    },
    handler: async (ctx, { conversationId, runId }) => {
        const conversation = await ctx.db.get(conversationId)
        // Fence: the reaper (or a newer turn) has taken ownership. Stop rather
        // than mutate state we no longer own.
        if (!conversation || conversation.runId !== runId) {
            return { kind: 'fenced' as const }
        }

        const pending = await ctx.db
            .query('whatsappInboundMessages')
            .withIndex('by_conversationId_and_status', (q) =>
                q.eq('conversationId', conversationId).eq('status', 'pending'),
            )
            .take(MAX_BATCH)

        if (pending.length === 0) {
            await ctx.db.patch(conversationId, {
                status: 'idle',
                runId: undefined,
                processingStartedAt: undefined,
            })
            return { kind: 'released' as const }
        }

        for (const message of pending) {
            await ctx.db.patch(message._id, {
                status: 'claimed',
                claimedByRunId: runId,
            })
        }

        return {
            kind: 'batch' as const,
            userId: conversation.userId ?? null,
            waId: conversation.waId,
            phoneNumberId: conversation.phoneNumberId,
            windowExpiresAt: conversation.windowExpiresAt,
            messages: pending.map((message) => ({
                id: message._id,
                type: message.type,
                text: message.text ?? null,
                mediaId: message.mediaId ?? null,
                sentAt: message.sentAt,
            })),
        }
    },
})

// Marks a claimed batch done. Failed messages are not retried automatically —
// retrying an LLM turn that already partially replied risks double-messaging
// the user, so failures are recorded and left for inspection.
export const finishBatch = internalMutation({
    args: {
        messageIds: v.array(v.id('whatsappInboundMessages')),
        status: v.union(v.literal('processed'), v.literal('failed')),
        failureReason: v.optional(v.string()),
    },
    handler: async (ctx, { messageIds, status, failureReason }) => {
        for (const messageId of messageIds) {
            await ctx.db.patch(messageId, { status, failureReason })
        }
        return null
    },
})

export const recordOutbound = internalMutation({
    args: {
        conversationId: v.id('whatsappConversations'),
        text: v.string(),
        wamid: v.optional(v.string()),
        status: v.union(
            v.literal('queued'),
            v.literal('sent'),
            v.literal('failed'),
        ),
        errorCode: v.optional(v.number()),
        errorMessage: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const now = Date.now()
        await ctx.db.insert('whatsappOutboundMessages', {
            ...args,
            createdAt: now,
            updatedAt: now,
        })
        return null
    },
})

// Status webhooks are the *only* evidence an outbound message was delivered.
// A send returning `200` + a wamid means queued and nothing more.
export const applyStatusUpdates = internalMutation({
    args: {
        statuses: v.array(
            v.object({
                wamid: v.string(),
                status: v.string(),
                errorCode: v.optional(v.number()),
                errorMessage: v.optional(v.string()),
            }),
        ),
    },
    handler: async (ctx, { statuses }) => {
        for (const update of statuses) {
            const row = await ctx.db
                .query('whatsappOutboundMessages')
                .withIndex('by_wamid', (q) => q.eq('wamid', update.wamid))
                .first()
            if (!row) continue

            const status =
                update.status === 'delivered' ||
                update.status === 'read' ||
                update.status === 'sent' ||
                update.status === 'failed'
                    ? update.status
                    : row.status
            // Statuses arrive out of order — a `read` can precede its
            // `delivered` — so never regress a terminal state.
            const rank = {
                queued: 0,
                sent: 1,
                delivered: 2,
                read: 3,
                failed: 4,
            }
            if (rank[status] < rank[row.status]) continue

            await ctx.db.patch(row._id, {
                status,
                errorCode: update.errorCode ?? row.errorCode,
                errorMessage: update.errorMessage ?? row.errorMessage,
                updatedAt: Date.now(),
            })
            if (update.status === 'failed') {
                console.error(
                    `whatsapp outbound ${update.wamid} failed (${update.errorCode ?? 'no code'}): ${update.errorMessage ?? 'no message'}`,
                )
            }
        }
        return null
    },
})

// Passes ownership of a still-busy conversation to a fresh action, so a very
// chatty conversation is never dropped just because one action reached its
// execution limit. The new runId fences out the caller, which is about to exit.
export const handOffTurn = internalMutation({
    args: {
        conversationId: v.id('whatsappConversations'),
        runId: v.string(),
    },
    handler: async (ctx, { conversationId, runId }) => {
        const conversation = await ctx.db.get(conversationId)
        if (!conversation || conversation.runId !== runId) return null
        const nextRunId = crypto.randomUUID()
        await ctx.db.patch(conversationId, {
            runId: nextRunId,
            processingStartedAt: Date.now(),
        })
        await ctx.scheduler.runAfter(
            0,
            internal.whatsapp.nodeActions.runAgentTurn,
            { conversationId, runId: nextRunId },
        )
        return null
    },
})

// Without this, one crashed action leaves a conversation `processing` forever
// and the user is permanently ignored — every later message writes a row and
// declines to start a turn. Scheduled from crons.ts.
export const releaseStuckTurns = internalMutation({
    args: {},
    handler: async (ctx) => {
        const cutoff = Date.now() - STUCK_AFTER_MS
        const stuck = await ctx.db
            .query('whatsappConversations')
            .withIndex('by_status_and_processingStartedAt', (q) =>
                q.eq('status', 'processing').lt('processingStartedAt', cutoff),
            )
            .take(REAPER_LIMIT)

        for (const conversation of stuck) {
            console.error(
                `whatsapp conversation ${conversation._id} (${conversation.waId}) stuck in processing since ${conversation.processingStartedAt}; releasing`,
            )
            // Clearing runId fences the old turn out for good.
            await ctx.db.patch(conversation._id, {
                status: 'idle',
                runId: undefined,
                processingStartedAt: undefined,
            })
            // Messages it claimed but never finished go back on the queue.
            const claimed = await ctx.db
                .query('whatsappInboundMessages')
                .withIndex('by_conversationId_and_status', (q) =>
                    q
                        .eq('conversationId', conversation._id)
                        .eq('status', 'claimed'),
                )
                .take(MAX_BATCH)
            for (const message of claimed) {
                await ctx.db.patch(message._id, {
                    status: 'pending',
                    claimedByRunId: undefined,
                })
            }
            await maybeStartTurn(ctx, conversation._id)
        }
        return null
    },
})
