// Unit tests for the agent-report submission rules, outside convex/ so the
// Convex bundler never sees them. `normalizeReport` is the whole of the
// mutation's validation and is pure by design (no ctx, no fetch), so the rules
// that decide what reaches the moderation queue are testable on their own.

import {
    AGENT_REPORT_MAX_NOTE_LENGTH,
    AGENT_REPORT_MAX_SNIPPET_LENGTH,
    AGENT_REPORT_REASONS,
    isAgentReportReason,
    isAgentReportScope,
    isAgentReportStatus,
} from '@wallet-bot/shared'
import { describe, expect, it } from 'vitest'
import { normalizeReport } from '../convex/agentReports/utils'

const responseReport = (overrides: Record<string, string> = {}) => ({
    reason: 'offensive',
    scope: 'response',
    reportedText: 'something the agent said',
    ...overrides,
})

describe('normalizeReport — reason and scope', () => {
    it('accepts every reason the clients can offer', () => {
        for (const reason of AGENT_REPORT_REASONS) {
            const result = normalizeReport(responseReport({ reason }))
            expect(result.ok).toBe(true)
        }
    })

    it('rejects a reason outside the shared set', () => {
        const result = normalizeReport(responseReport({ reason: 'spam' }))
        expect(result).toEqual({ ok: false, error: 'reason_invalid' })
    })

    it('rejects an unknown scope', () => {
        const result = normalizeReport(responseReport({ scope: 'everything' }))
        expect(result).toEqual({ ok: false, error: 'scope_invalid' })
    })

    it('checks the reason before the scope, so a doubly bad payload names the reason', () => {
        const result = normalizeReport({ reason: 'spam', scope: 'everything' })
        expect(result).toEqual({ ok: false, error: 'reason_invalid' })
    })
})

describe('normalizeReport — the reported text', () => {
    it('rejects a response-scoped report with no text', () => {
        const result = normalizeReport({
            reason: 'offensive',
            scope: 'response',
        })
        expect(result).toEqual({ ok: false, error: 'report_invalid' })
    })

    it('rejects a response-scoped report whose text is only whitespace', () => {
        const result = normalizeReport(
            responseReport({ reportedText: '   \n' }),
        )
        expect(result).toEqual({ ok: false, error: 'report_invalid' })
    })

    it('accepts a session-scoped report with no text at all', () => {
        // The fallback for a reply that was audio-only or has scrolled away:
        // the moderator reads it from the replicated history instead.
        const result = normalizeReport({
            reason: 'dangerous',
            scope: 'session',
            sessionId: 'session-1',
        })
        expect(result.ok).toBe(true)
        if (!result.ok) return
        expect(result.value.reportedText).toBeUndefined()
        expect(result.value.sessionId).toBe('session-1')
    })

    it('truncates an overlong response instead of rejecting it', () => {
        const long = 'a'.repeat(AGENT_REPORT_MAX_SNIPPET_LENGTH + 500)
        const result = normalizeReport(responseReport({ reportedText: long }))
        expect(result.ok).toBe(true)
        if (!result.ok) return
        expect(result.value.reportedText).toHaveLength(
            AGENT_REPORT_MAX_SNIPPET_LENGTH,
        )
    })

    it('truncates the preceding user turn on the same cap', () => {
        const long = 'b'.repeat(AGENT_REPORT_MAX_SNIPPET_LENGTH + 1)
        const result = normalizeReport(
            responseReport({ precedingUserText: long }),
        )
        expect(result.ok).toBe(true)
        if (!result.ok) return
        expect(result.value.precedingUserText).toHaveLength(
            AGENT_REPORT_MAX_SNIPPET_LENGTH,
        )
    })

    it('trims surrounding whitespace off the snapshots', () => {
        const result = normalizeReport(
            responseReport({
                reportedText: '  the reply  ',
                precedingUserText: '\tthe question\n',
            }),
        )
        expect(result.ok).toBe(true)
        if (!result.ok) return
        expect(result.value.reportedText).toBe('the reply')
        expect(result.value.precedingUserText).toBe('the question')
    })
})

describe('normalizeReport — the note and session pointer', () => {
    it('truncates an overlong note', () => {
        const long = 'c'.repeat(AGENT_REPORT_MAX_NOTE_LENGTH + 10)
        const result = normalizeReport(responseReport({ note: long }))
        expect(result.ok).toBe(true)
        if (!result.ok) return
        expect(result.value.note).toHaveLength(AGENT_REPORT_MAX_NOTE_LENGTH)
    })

    it('drops an empty note rather than storing a blank string', () => {
        const result = normalizeReport(responseReport({ note: '   ' }))
        expect(result.ok).toBe(true)
        if (!result.ok) return
        expect(result.value.note).toBeUndefined()
    })

    it('drops an empty session id', () => {
        const result = normalizeReport(responseReport({ sessionId: '  ' }))
        expect(result.ok).toBe(true)
        if (!result.ok) return
        expect(result.value.sessionId).toBeUndefined()
    })
})

describe('shared guards', () => {
    it('recognizes the values both clients send', () => {
        expect(isAgentReportReason('misleading')).toBe(true)
        expect(isAgentReportReason('MISLEADING')).toBe(false)
        expect(isAgentReportScope('session')).toBe(true)
        expect(isAgentReportScope('turn')).toBe(false)
        expect(isAgentReportStatus('actioned')).toBe(true)
        expect(isAgentReportStatus('open')).toBe(false)
    })
})
