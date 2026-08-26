import { api } from '@wallet-bot/backend/api'
import {
    AGENT_REPORT_MAX_NOTE_LENGTH,
    AGENT_REPORT_REASONS,
    type AgentReportReason,
} from '@wallet-bot/shared'
import { Button, IconButton, TextField } from 'actify'
import { useMutation } from 'convex/react'
import { useState } from 'react'
import { toast } from 'sonner'
import { BottomSheet } from '@/components/m3/bottom-sheet'
import { Icon } from '@/components/m3/icon'
import { useI18n, useT } from '@/lib/i18n'

/**
 * What the report points at. `response` carries the flagged turn's text;
 * `session` is the fallback for a reply that was voice-only or has scrolled
 * away, and names the conversation instead.
 */
export type ReportTarget =
    | {
          scope: 'response'
          /** The chat message id, so the bubble can be marked afterwards. */
          messageId: string
          reportedText: string
          precedingUserText?: string
          occurredAt: Date
      }
    | { scope: 'session' }

type ReportResponseSheetProps = {
    open: boolean
    onOpenChange: (open: boolean) => void
    target: ReportTarget | null
    sessionId?: string
    model?: string
    onReported?: (messageId: string) => void
}

/**
 * The in-app path for flagging something Gasti said, required by Google Play's
 * AI-Generated Content policy and by Apple's guidelines 1.2 / 4.7.1: a user must
 * be able to report offensive generated content without leaving the app.
 *
 * The flagged text is shown read-only before sending. The report stores a copy
 * of it server-side, and a sheet that sent it silently would hide that.
 */
export function ReportResponseSheet({
    open,
    onOpenChange,
    target,
    sessionId,
    model,
    onReported,
}: ReportResponseSheetProps) {
    const t = useT()
    const { locale } = useI18n()

    const [reason, setReason] = useState<AgentReportReason | null>(null)
    const [note, setNote] = useState('')
    const [sending, setSending] = useState(false)
    /**
     * The last failure, shown inside the sheet. A toast alone puts the reason
     * outside the surface the user is looking at, and on the narrow layout the
     * sheet covers where it appears.
     */
    const [error, setError] = useState<string | null>(null)

    const submitReport = useMutation(api.v1.agentReports.mutations.submit)

    const close = () => {
        setReason(null)
        setNote('')
        setError(null)
        onOpenChange(false)
    }

    const send = async () => {
        if (!target) return
        if (!reason) {
            setError(t.agentReport.reasonRequired)
            return
        }
        // Cheap and certain: the browser already knows there is no network, so
        // there is no reason to spend the timeout finding out.
        if (!navigator.onLine) {
            setError(t.agentReport.offline)
            return
        }

        setSending(true)
        setError(null)
        const toastId = toast.loading(t.agentReport.sending)
        try {
            const result = await submitReport({
                reason,
                scope: target.scope,
                note: note.trim() || undefined,
                ...(target.scope === 'response'
                    ? {
                          reportedText: target.reportedText,
                          precedingUserText: target.precedingUserText,
                          occurredAt: BigInt(target.occurredAt.getTime()),
                      }
                    : {}),
                sessionId,
                model,
                platform: 'web',
                locale,
            })
            if (!result.ok) throw new ReportError(result.error)

            toast.success(t.agentReport.sent, { id: toastId })
            if (target.scope === 'response') onReported?.(target.messageId)
            close()
        } catch (caught) {
            // The sheet stays open with the reason and the note intact, so a
            // rate limit never costs the user what they wrote. The reason goes
            // in the sheet, not in the toast: the toast is gone in seconds and
            // the retry button is here.
            console.error('sending agent report failed', caught)
            toast.dismiss(toastId)
            setError(errorMessage(caught, t))
        } finally {
            setSending(false)
        }
    }

    const isSession = target?.scope === 'session'

    return (
        <BottomSheet
            open={open}
            onOpenChange={(next) => {
                if (!next && !sending) close()
            }}
            title={t.agentReport.title}
            showTitle
            footer={
                <div className="flex gap-3">
                    <Button
                        variant="outlined"
                        className="flex-1"
                        isDisabled={sending}
                        onPress={close}
                    >
                        {t.common.cancel}
                    </Button>
                    <Button
                        variant="filled"
                        className="flex-1"
                        isDisabled={sending || reason === null}
                        onPress={() => void send()}
                    >
                        {t.agentReport.send}
                    </Button>
                </div>
            }
        >
            <div className="flex flex-col gap-5 px-4 pb-6">
                <p className="m3-body-medium text-on-surface-variant">
                    {isSession
                        ? t.agentReport.sessionSubtitle
                        : t.agentReport.subtitle}
                </p>

                {target?.scope === 'response' ? (
                    <div className="flex flex-col gap-1">
                        <span className="m3-label-medium text-on-surface-variant">
                            {t.agentReport.reportedTextLabel}
                        </span>
                        <blockquote className="m3-body-medium max-h-40 overflow-y-auto whitespace-pre-wrap rounded-xl bg-surface-container-high px-3 py-2">
                            {target.reportedText}
                        </blockquote>
                    </div>
                ) : (
                    <p className="m3-body-small text-on-surface-variant">
                        {t.agentReport.sessionNotice}
                    </p>
                )}

                <fieldset className="flex flex-col gap-2">
                    <legend className="m3-label-medium text-on-surface-variant">
                        {t.agentReport.reasonLabel}
                    </legend>
                    <div className="flex flex-wrap gap-2">
                        {AGENT_REPORT_REASONS.map((option) => (
                            <button
                                key={option}
                                type="button"
                                disabled={sending}
                                aria-pressed={reason === option}
                                onClick={() => {
                                    setReason(option)
                                    setError(null)
                                }}
                                className={`m3-label-large rounded-lg border px-3 py-2 transition-colors disabled:opacity-50 ${
                                    reason === option
                                        ? 'border-secondary bg-secondary-container text-on-secondary-container'
                                        : 'border-outline-variant text-on-surface-variant hover:bg-surface-container-high'
                                }`}
                            >
                                {reasonLabel(option, t)}
                            </button>
                        ))}
                    </div>
                </fieldset>

                {/*
                 * `className` reaches the textarea element itself (actify
                 * spreads it there), which is how the field gets its height —
                 * the component takes no `rows`.
                 */}
                <TextField
                    variant="outlined"
                    className="min-h-24 w-full"
                    type="textarea"
                    label={t.agentReport.noteLabel}
                    placeholder={t.agentReport.notePlaceholder}
                    value={note}
                    onChange={setNote}
                    maxLength={AGENT_REPORT_MAX_NOTE_LENGTH}
                    isDisabled={sending}
                />

                <p className="m3-body-small text-on-surface-variant">
                    {t.agentReport.privacyNotice}
                </p>

                {error ? (
                    <div
                        role="alert"
                        className="flex items-start gap-2 rounded-xl bg-error-container px-3 py-2 text-on-error-container"
                    >
                        <Icon name="error" size={20} className="mt-0.5" />
                        <p className="m3-body-medium flex-1">{error}</p>
                        <IconButton
                            aria-label={t.agentReport.errorDismiss}
                            onPress={() => setError(null)}
                            className="text-on-error-container"
                        >
                            <Icon name="close" size={18} />
                        </IconButton>
                    </div>
                ) : null}
            </div>
        </BottomSheet>
    )
}

/** A rejection the server explained, so the sheet can show its own copy. */
class ReportError extends Error {
    reason: string

    constructor(reason: string) {
        super(reason)
        this.reason = reason
    }
}

function reasonLabel(
    reason: AgentReportReason,
    t: ReturnType<typeof useT>,
): string {
    switch (reason) {
        case 'offensive':
            return t.agentReport.reasonOffensive
        case 'sexual':
            return t.agentReport.reasonSexual
        case 'dangerous':
            return t.agentReport.reasonDangerous
        case 'misleading':
            return t.agentReport.reasonMisleading
        case 'privacy':
            return t.agentReport.reasonPrivacy
        case 'other':
            return t.agentReport.reasonOther
    }
}

function errorMessage(error: unknown, t: ReturnType<typeof useT>): string {
    if (error instanceof ReportError) {
        if (error.reason === 'rate_limited') return t.agentReport.rateLimited
        return t.agentReport.failed
    }
    // A `TypeError` from `fetch` is the connection; anything else is ours.
    if (error instanceof TypeError) return t.agentReport.offline
    return t.agentReport.failed
}
