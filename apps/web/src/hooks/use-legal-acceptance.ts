import { api } from '@wallet-bot/backend/api'
import {
    LEGAL_DOCUMENTS,
    type LegalDocument,
    type LegalDocumentStatus,
} from '@wallet-bot/shared'
import { useQuery } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'

export type LegalAcceptanceStatus = FunctionReturnType<
    typeof api.v1.legal.queries.acceptanceStatus
>

/**
 * What the signed-in user still owes on the Terms and the Privacy Policy.
 *
 * `undefined` while the query is in flight — callers must not treat that as
 * "nothing owed" (it would flash the app and then bounce to the gate).
 */
export function useLegalAcceptance(): LegalAcceptanceStatus | undefined {
    return useQuery(api.v1.legal.queries.acceptanceStatus)
}

/** The documents the gate has to ask about, in a stable order. */
export function pendingLegalDocuments(
    status: LegalAcceptanceStatus,
): LegalDocument[] {
    return LEGAL_DOCUMENTS.filter(
        (document) => documentStatus(status, document) !== 'current',
    )
}

export function documentStatus(
    status: LegalAcceptanceStatus,
    document: LegalDocument,
): LegalDocumentStatus {
    return status[document].status
}

/** Nothing was ever accepted: this is a first acceptance, not an update. */
export function isFirstAcceptance(status: LegalAcceptanceStatus): boolean {
    return LEGAL_DOCUMENTS.every(
        (document) => status[document].accepted === null,
    )
}

/**
 * Session-scoped "Later" dismissal.
 *
 * Only reachable while the grace period is running (`prompt` without
 * `blocking`), so at worst the user is nudged again on their next visit —
 * which is the point of a nudge. `sessionStorage` rather than component state
 * because the gate is a route: navigating away from it must not re-arm the
 * redirect, and a reload inside the same tab session shouldn't nag again.
 * Keyed by user and by the versions being asked for, so a newer version
 * always prompts afresh.
 */
export function legalDismissalKey(
    userId: string,
    status: LegalAcceptanceStatus,
): string {
    return `legal-later:${userId}:${status.terms.current}:${status.privacy.current}`
}

export function isLegalPromptDismissed(key: string): boolean {
    try {
        return sessionStorage.getItem(key) === '1'
    } catch {
        // Private-mode/blocked storage: nudge every time rather than crash.
        return false
    }
}

export function dismissLegalPrompt(key: string): void {
    try {
        sessionStorage.setItem(key, '1')
    } catch {
        // Best effort — see above.
    }
}
