import { api } from '@wallet-bot/backend/api'
import {
    AGENT_REPORT_STATUSES,
    type AgentReportStatus,
    isAgentReportReason,
} from '@wallet-bot/shared'
import { IconButton } from 'actify'
import { useMutation, usePaginatedQuery } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
import { Button } from '@/components/ui/button'
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle,
} from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { Textarea } from '@/components/ui/textarea'
import { useFormatLocale, useT } from '@/lib/i18n'

const PAGE_SIZE = 20

/**
 * The moderation queue for reported agent responses.
 *
 * Google Play asks developers to use these reports "to inform content filtering
 * and moderation", so the queue is not a read-only list: every report gets a
 * status and a note saying what was done about it.
 *
 * The rows hold slices of someone's conversation, which is why every read here
 * goes through an admin-guarded query and the page refuses to render for anyone
 * else.
 */
export function AgentReports() {
    const t = useT()
    const navigate = useNavigate()
    const [status, setStatus] = useState<AgentReportStatus>('pending')

    const {
        results: reports,
        status: pageStatus,
        loadMore,
    } = usePaginatedQuery(
        api.v1.agentReports.queries.list,
        { status },
        { initialNumItems: PAGE_SIZE },
    )

    return (
        <>
            <AppBar
                title={t.adminReports.title}
                leading={
                    <IconButton
                        aria-label={t.adminReports.back}
                        onPress={() => navigate('/admin')}
                        className="text-on-surface-variant"
                    >
                        <Icon name="arrow_back" />
                    </IconButton>
                }
            />
            <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
                <p className="text-sm text-muted-foreground">
                    {t.adminReports.subtitle}
                </p>

                <div className="flex flex-wrap gap-2">
                    {AGENT_REPORT_STATUSES.map((option) => (
                        <Button
                            key={option}
                            size="sm"
                            variant={status === option ? 'default' : 'outline'}
                            onClick={() => setStatus(option)}
                        >
                            {statusLabel(option, t)}
                        </Button>
                    ))}
                </div>

                {pageStatus === 'LoadingFirstPage' ? (
                    <>
                        <Skeleton className="h-40 w-full shrink-0" />
                        <Skeleton className="h-40 w-full shrink-0" />
                    </>
                ) : reports.length === 0 ? (
                    <p className="py-8 text-center text-sm text-muted-foreground">
                        {t.adminReports.empty}
                    </p>
                ) : (
                    reports.map((report) => (
                        <ReportCard key={report.id} report={report} />
                    ))
                )}

                {pageStatus === 'CanLoadMore' && (
                    <Button
                        variant="outline"
                        onClick={() => loadMore(PAGE_SIZE)}
                    >
                        {t.adminReports.loadMore}
                    </Button>
                )}
            </div>
        </>
    )
}

type ReportRow = FunctionReturnType<
    typeof api.v1.agentReports.queries.list
>['page'][number]

function ReportCard({ report }: { report: ReportRow }) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const review = useMutation(api.v1.agentReports.mutations.review)
    const [reviewNote, setReviewNote] = useState(report.reviewNote ?? '')
    const [saving, setSaving] = useState(false)

    const save = (next: AgentReportStatus) => {
        setSaving(true)
        toast.promise(
            review({
                reportId: report.id,
                status: next,
                reviewNote: reviewNote.trim() || undefined,
            }).finally(() => setSaving(false)),
            {
                loading: t.common.saving,
                success: t.adminReports.saved,
                error: t.adminReports.saveFailed,
            },
        )
    }

    return (
        // shrink-0: a flex child defaults to shrinking, so without this the
        // cards compress to fit the viewport and clip their own contents
        // instead of overflowing the scroll container above.
        <Card className="shrink-0">
            <CardHeader>
                <CardTitle className="flex flex-wrap items-center gap-2">
                    <Icon name="flag" filled size={18} />
                    {reasonLabel(report.reason, t)}
                    <span className="rounded-full bg-muted px-2 py-0.5 text-xs font-normal">
                        {report.scope === 'session'
                            ? t.adminReports.scopeSession
                            : t.adminReports.scopeResponse}
                    </span>
                </CardTitle>
                <CardDescription>
                    {formatMoment(report.createdAt, formatLocale)} ·{' '}
                    {report.platform}
                    {report.appVersion ? ` ${report.appVersion}` : ''} ·{' '}
                    {report.reporter === 'account'
                        ? t.adminReports.reporterAccount
                        : t.adminReports.reporterDevice}
                </CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
                {report.reportedText && (
                    <Field label={t.adminReports.reportedText}>
                        <blockquote className="max-h-56 overflow-y-auto whitespace-pre-wrap rounded-md bg-muted px-3 py-2 text-sm">
                            {report.reportedText}
                        </blockquote>
                    </Field>
                )}

                {report.precedingUserText && (
                    <Field label={t.adminReports.precedingUserText}>
                        <blockquote className="max-h-40 overflow-y-auto whitespace-pre-wrap rounded-md bg-muted px-3 py-2 text-sm">
                            {report.precedingUserText}
                        </blockquote>
                    </Field>
                )}

                {report.note && (
                    <Field label={t.adminReports.note}>
                        <p className="whitespace-pre-wrap text-sm">
                            {report.note}
                        </p>
                    </Field>
                )}

                <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs text-muted-foreground">
                    {report.sessionId && (
                        <>
                            <dt>{t.adminReports.session}</dt>
                            <dd className="truncate font-mono">
                                {report.sessionId}
                            </dd>
                        </>
                    )}
                    {report.model && (
                        <>
                            <dt>{t.adminReports.model}</dt>
                            <dd className="truncate">{report.model}</dd>
                        </>
                    )}
                </dl>

                <Field label={t.adminReports.reviewNote}>
                    <Textarea
                        value={reviewNote}
                        onChange={(event) => setReviewNote(event.target.value)}
                        placeholder={t.adminReports.reviewNotePlaceholder}
                        disabled={saving}
                    />
                </Field>

                <div className="flex flex-wrap gap-2">
                    {AGENT_REPORT_STATUSES.filter(
                        (option) => option !== report.status,
                    ).map((option) => (
                        <Button
                            key={option}
                            size="sm"
                            variant="outline"
                            disabled={saving}
                            onClick={() => save(option)}
                        >
                            {statusLabel(option, t)}
                        </Button>
                    ))}
                </div>
            </CardContent>
        </Card>
    )
}

function Field({
    label,
    children,
}: {
    label: string
    children: React.ReactNode
}) {
    return (
        <div className="flex flex-col gap-1">
            <span className="text-xs font-medium text-muted-foreground">
                {label}
            </span>
            {children}
        </div>
    )
}

function statusLabel(
    status: AgentReportStatus,
    t: ReturnType<typeof useT>,
): string {
    switch (status) {
        case 'pending':
            return t.adminReports.statusPending
        case 'reviewed':
            return t.adminReports.statusReviewed
        case 'actioned':
            return t.adminReports.statusActioned
        case 'dismissed':
            return t.adminReports.statusDismissed
    }
}

/**
 * `reason` arrives as a plain string — the column is `v.string()`, validated on
 * write against the shared set. A value this build doesn't know falls back to
 * "other" rather than rendering blank, so a row written by a newer client is
 * still triageable here.
 */
function reasonLabel(reason: string, t: ReturnType<typeof useT>): string {
    if (!isAgentReportReason(reason)) return t.agentReport.reasonOther
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

/** Timestamps travel as `v.int64()`, so they arrive as a bigint. */
function formatMoment(millis: bigint, locale: string): string {
    return new Date(Number(millis)).toLocaleString(locale, {
        dateStyle: 'medium',
        timeStyle: 'short',
    })
}
