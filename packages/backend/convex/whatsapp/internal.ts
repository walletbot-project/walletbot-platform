import { v } from 'convex/values'
import { internal } from '../_generated/api'
import type { Doc, Id } from '../_generated/dataModel'
import {
    internalMutation,
    internalQuery,
    type MutationCtx,
} from '../_generated/server'
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

// Wrong codes tolerated before a conversation is put on ice. Low, because a
// legitimate user pastes a deep link or copies a code off their own screen —
// repeated misses mean someone is guessing.
const MAX_LINK_ATTEMPTS = 5
const LINK_BLOCK_MS = 15 * 60 * 1000

// How long a code row survives past its expiry, so "that code already expired"
// stays answerable for a while after the fact.
const LINK_CODE_RETENTION_MS = 24 * 60 * 60 * 1000
const PURGE_LIMIT = 100

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

// Resolves a batch of candidate codes against the pending link codes and, on a
// match, binds the conversation to that account.
//
// One mutation, one transaction, on purpose. The check ("is this code valid
// and unused?") and the write ("consume it and link") must be atomic, or the
// same code could be redeemed twice by two conversations racing — which would
// hand a second, unrelated WhatsApp number access to someone's finances.
//
// Not every miss is punished. Re-sending a code this same conversation already
// redeemed, or one that simply expired, is what a confused legitimate user
// does; only a wrong code, or one belonging to a different number, counts
// against the attempt limit.
export const tryLink = internalMutation({
    args: {
        conversationId: v.id('whatsappConversations'),
        runId: v.string(),
        candidates: v.array(v.string()),
    },
    handler: async (ctx, { conversationId, runId, candidates }) => {
        const conversation = await ctx.db.get(conversationId)
        if (!conversation || conversation.runId !== runId) {
            return { kind: 'fenced' as const }
        }
        if (conversation.userId !== undefined) {
            return { kind: 'already_linked' as const }
        }

        const now = Date.now()
        if (
            conversation.linkBlockedUntil !== undefined &&
            now < conversation.linkBlockedUntil
        ) {
            return {
                kind: 'blocked' as const,
                until: conversation.linkBlockedUntil,
            }
        }
        if (candidates.length === 0) {
            return { kind: 'no_code' as const }
        }

        for (const candidate of candidates) {
            const row = await ctx.db
                .query('whatsappLinkCodes')
                .withIndex('by_code', (q) => q.eq('code', candidate))
                .unique()
            if (!row) continue

            if (row.consumedAt !== undefined) {
                // Their own code, sent twice. Harmless.
                if (row.consumedByWaId === conversation.waId) {
                    return { kind: 'already_used' as const }
                }
                // Someone else's code. That is worth counting.
                break
            }
            if (now >= row.expiresAt) {
                return { kind: 'expired' as const }
            }

            await ctx.db.patch(row._id, {
                consumedAt: now,
                consumedByWaId: conversation.waId,
            })
            await ctx.db.patch(conversationId, {
                userId: row.userId,
                linkedAt: now,
                failedLinkAttempts: undefined,
                linkBlockedUntil: undefined,
            })
            return { kind: 'linked' as const }
        }

        const attempts = (conversation.failedLinkAttempts ?? 0) + 1
        const blocked = attempts >= MAX_LINK_ATTEMPTS
        await ctx.db.patch(conversationId, {
            failedLinkAttempts: attempts,
            linkBlockedUntil: blocked ? now + LINK_BLOCK_MS : undefined,
        })
        return {
            kind: 'invalid' as const,
            attemptsLeft: Math.max(0, MAX_LINK_ATTEMPTS - attempts),
        }
    },
})

// Consumed and expired codes are kept for a while so a user re-sending one
// gets a useful answer rather than "wrong code". Once they are stale they are
// only a liability, and keeping the table small is what makes the collision
// check in createLinkCode cheap. Scheduled from crons.ts.
export const purgeExpiredLinkCodes = internalMutation({
    args: {},
    handler: async (ctx) => {
        const cutoff = Date.now() - LINK_CODE_RETENTION_MS
        const stale = await ctx.db
            .query('whatsappLinkCodes')
            .withIndex('by_expiresAt', (q) => q.lt('expiresAt', cutoff))
            .take(PURGE_LIMIT)
        for (const row of stale) {
            await ctx.db.delete(row._id)
        }
        return null
    },
})

// How much of the conversation the agent is shown. WhatsApp threads are long
// and mostly irrelevant — a user who logged groceries in March does not want
// that influencing today's answer — while the last few exchanges are what make
// "y otro igual" or "cambialo a 3000" resolvable at all.
const HISTORY_MESSAGES = 20
// Anything older than this is not context, it is a different conversation.
const HISTORY_MAX_AGE_MS = 24 * 60 * 60 * 1000
// One pathological message must not push everything useful out of the window.
const HISTORY_MAX_CHARS = 1500

// The recent exchange, oldest first, for seeding the model's context.
//
// Only messages already dealt with are included: the batch the current turn is
// holding is `claimed`, and the caller appends those itself as the live user
// turn. Including them here would duplicate them.
export const recentHistory = internalQuery({
    args: { conversationId: v.id('whatsappConversations') },
    handler: async (ctx, { conversationId }) => {
        const cutoff = Date.now() - HISTORY_MAX_AGE_MS

        const inbound = await ctx.db
            .query('whatsappInboundMessages')
            .withIndex('by_conversationId_and_receivedAt', (q) =>
                q.eq('conversationId', conversationId).gt('receivedAt', cutoff),
            )
            .order('desc')
            .take(HISTORY_MESSAGES)

        const outbound = await ctx.db
            .query('whatsappOutboundMessages')
            .withIndex('by_conversationId', (q) =>
                q.eq('conversationId', conversationId),
            )
            .order('desc')
            .take(HISTORY_MESSAGES)

        const entries: { at: number; role: 'user' | 'model'; text: string }[] =
            []
        for (const message of inbound) {
            if (message.status !== 'processed' && message.status !== 'failed') {
                continue
            }
            const text = message.text?.trim()
            if (!text) continue
            entries.push({
                at: message.receivedAt,
                role: 'user',
                text: text.slice(0, HISTORY_MAX_CHARS),
            })
        }
        for (const message of outbound) {
            if (message.createdAt <= cutoff) continue
            // A send that failed never reached the user, so pretending we said
            // it would make the model reason from a message they never saw.
            if (message.status === 'failed') continue
            const text = message.text.trim()
            if (text.length === 0) continue
            entries.push({
                at: message.createdAt,
                role: 'model',
                text: text.slice(0, HISTORY_MAX_CHARS),
            })
        }

        entries.sort((a, b) => a.at - b.at)
        return entries
            .slice(-HISTORY_MESSAGES)
            .map(({ role, text }) => ({ role, text }))
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
