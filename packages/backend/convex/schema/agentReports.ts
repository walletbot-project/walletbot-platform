import { defineTable } from 'convex/server'
import { v } from 'convex/values'

/**
 * Reports of an agent response, filed from the chat itself.
 *
 * Required by Google Play's AI-Generated Content policy ("in-app user reporting
 * or flagging features ... without needing to exit the app") and by Apple's
 * guidelines 1.2 / 4.7.1. Reachable by signed-in users AND by native local-only
 * accounts, so the reporter is recorded as EITHER `userId` or `deviceId`, never
 * both — the same convention `feedback` uses.
 *
 * `reportedText` is a snapshot of the flagged turn as it was rendered, not a
 * pointer. `voiceSessionEvents` stores transcript *deltas* rather than whole
 * turns, and a local-only account never replicates history at all, so a report
 * that only pointed at a session would frequently name evidence nobody can
 * read. `sessionId` / `occurredAt` stay alongside it so a moderator can pull the
 * surrounding conversation when it does exist.
 */
export const agentReports = defineTable({
    /** One of `AGENT_REPORT_REASONS`, validated against the shared set. */
    reason: v.string(),
    /** 'response' (carries `reportedText`) or 'session' (names the session). */
    scope: v.string(),
    /** Optional free text the reporter added. */
    note: v.optional(v.string()),
    /** The flagged agent turn, truncated to the shared cap. */
    reportedText: v.optional(v.string()),
    /** The user turn that prompted it, so the response can be read in context. */
    precedingUserText: v.optional(v.string()),
    /** Pointers into `voiceSessions` / `voiceSessionEvents` when available. */
    sessionId: v.optional(v.string()),
    model: v.optional(v.string()),
    occurredAt: v.optional(v.int64()),
    /** Set for a signed-in reporter. */
    userId: v.optional(v.string()),
    /** Set instead of `userId` for a native local-only account. */
    deviceId: v.optional(v.string()),
    /** 'web' | 'android' | 'ios' | 'macos' | 'unknown' — evidence, not a gate. */
    platform: v.string(),
    appVersion: v.optional(v.string()),
    locale: v.optional(v.string()),
    /** One of `AGENT_REPORT_STATUSES`. New rows are 'pending'. */
    status: v.string(),
    reviewedBy: v.optional(v.string()),
    reviewedAt: v.optional(v.int64()),
    reviewNote: v.optional(v.string()),
    createdAt: v.int64(),
})
    // The moderation queue's only read path: oldest pending first.
    .index('by_status_and_createdAt', ['status', 'createdAt'])
    .index('by_userId', ['userId'])
    .index('by_createdAt', ['createdAt'])
