/**
 * Reporting an agent response, shared by both clients' sheets and the server's
 * validation so the reason set and the caps can't drift.
 *
 * Google Play's AI-Generated Content policy requires an in-app way to flag
 * offensive AI output without leaving the app, and Apple asks for the same
 * through guidelines 1.2 and 4.7.1. The reason codes below are what the sheets
 * offer and what `v1/agentReports/mutations:submit` accepts.
 */

/** Why the response was reported. Both clients have copy for each one. */
export const AGENT_REPORT_REASONS = [
    /** Hate, harassment or violent content. */
    'offensive',
    /** Sexual or adult content. */
    'sexual',
    /** Self-harm, illegal or otherwise dangerous instructions. */
    'dangerous',
    /** False or harmful financial claims stated as fact. */
    'misleading',
    /** Surfaced data it should not have. */
    'privacy',
    'other',
] as const

export type AgentReportReason = (typeof AGENT_REPORT_REASONS)[number]

/**
 * What the report points at.
 *
 * `response` carries the flagged turn's text. `session` is the fallback for a
 * reply that was audio-only or has already scrolled away: it names the session
 * and leaves the moderator to read it from the replicated history.
 */
export const AGENT_REPORT_SCOPES = ['response', 'session'] as const

export type AgentReportScope = (typeof AGENT_REPORT_SCOPES)[number]

/** Where a report sits in the moderation queue. */
export const AGENT_REPORT_STATUSES = [
    'pending',
    'reviewed',
    'actioned',
    'dismissed',
] as const

export type AgentReportStatus = (typeof AGENT_REPORT_STATUSES)[number]

/** Longest note the user can add to a report, in characters. */
export const AGENT_REPORT_MAX_NOTE_LENGTH = 2000

/**
 * Longest transcript snapshot stored per report, in characters. The server
 * truncates rather than rejecting: the client sends whatever the bubble held,
 * and a long reply must not turn into an error the user can't act on.
 */
export const AGENT_REPORT_MAX_SNIPPET_LENGTH = 4000

export const isAgentReportReason = (
    value: string,
): value is AgentReportReason =>
    (AGENT_REPORT_REASONS as readonly string[]).includes(value)

export const isAgentReportScope = (value: string): value is AgentReportScope =>
    (AGENT_REPORT_SCOPES as readonly string[]).includes(value)

export const isAgentReportStatus = (
    value: string,
): value is AgentReportStatus =>
    (AGENT_REPORT_STATUSES as readonly string[]).includes(value)
