import {
    AGENT_REPORT_MAX_NOTE_LENGTH,
    AGENT_REPORT_MAX_SNIPPET_LENGTH,
    type AgentReportReason,
    type AgentReportScope,
    isAgentReportReason,
    isAgentReportScope,
} from '@wallet-bot/shared'

export { AGENT_REPORT_MAX_NOTE_LENGTH, AGENT_REPORT_MAX_SNIPPET_LENGTH }

/** How long a report is kept before the retention cron reclaims it. */
export const AGENT_REPORT_RETENTION_MS = 365 * 24 * 60 * 60 * 1000

/** Cap on the review note an admin writes when triaging. */
export const MAX_REVIEW_NOTE_LENGTH = 2000

/** Why a report was rejected. Mirrored in both clients' copy. */
export type AgentReportError =
    | 'rate_limited'
    | 'unidentified_client'
    | 'reason_invalid'
    | 'scope_invalid'
    | 'report_invalid'

export type AgentReportResult =
    | { ok: true }
    | { ok: false; error: AgentReportError; retryAfter?: number }

/**
 * Trims a client-supplied snippet to the shared cap. Truncates rather than
 * rejecting: the client sends whatever the bubble held, and a long reply must
 * not become an error the reporter cannot act on.
 */
export function truncateSnippet(value: string | undefined): string | undefined {
    const trimmed = value?.trim()
    if (!trimmed) return undefined
    return trimmed.slice(0, AGENT_REPORT_MAX_SNIPPET_LENGTH)
}

export type ReportInput = {
    reason: string
    scope: string
    note?: string
    reportedText?: string
    precedingUserText?: string
    sessionId?: string
}

export type NormalizedReport = {
    reason: AgentReportReason
    scope: AgentReportScope
    note?: string
    reportedText?: string
    precedingUserText?: string
    sessionId?: string
}

/**
 * The whole of the submission's validation, kept pure so it can be tested
 * without a Convex context and so the mutation reads as identity → validate →
 * limit → write.
 */
export function normalizeReport(
    input: ReportInput,
):
    | { ok: true; value: NormalizedReport }
    | { ok: false; error: AgentReportError } {
    if (!isAgentReportReason(input.reason)) {
        return { ok: false, error: 'reason_invalid' }
    }
    if (!isAgentReportScope(input.scope)) {
        return { ok: false, error: 'scope_invalid' }
    }

    const reportedText = truncateSnippet(input.reportedText)
    // A response-scoped report with nothing to look at is not a report. The
    // session-scoped fallback is the path for a reply that was audio-only or
    // has already scrolled away.
    if (input.scope === 'response' && !reportedText) {
        return { ok: false, error: 'report_invalid' }
    }

    const note = input.note?.trim().slice(0, AGENT_REPORT_MAX_NOTE_LENGTH)
    const precedingUserText = truncateSnippet(input.precedingUserText)
    const sessionId = input.sessionId?.trim()

    return {
        ok: true,
        value: {
            reason: input.reason,
            scope: input.scope,
            ...(note ? { note } : {}),
            ...(reportedText ? { reportedText } : {}),
            ...(precedingUserText ? { precedingUserText } : {}),
            ...(sessionId ? { sessionId } : {}),
        },
    }
}
