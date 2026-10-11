import { api } from '@wallet-bot/backend/api'
import { usePaginatedQuery } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import { Link, useParams } from 'react-router-dom'
import { Button, buttonVariants } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { formatMoment } from '@/lib/format-moment'
import { useFormatLocale, useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'

const SESSIONS_PAGE_SIZE = 20
const EVENTS_PAGE_SIZE = 100

/**
 * Voice and chat sessions, newest first. These are people's private
 * conversations, so the list only names the session; the text is a click away
 * on the detail route.
 */
export function Transcripts() {
    const t = useT()
    const formatLocale = useFormatLocale()
    const {
        results: sessions,
        status,
        loadMore,
    } = usePaginatedQuery(
        api.v1.admin.queries.listTranscriptSessions,
        {},
        { initialNumItems: SESSIONS_PAGE_SIZE },
    )

    return (
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
            <p className="text-sm text-muted-foreground">
                {t.admin.transcripts.subtitle}
            </p>

            {status === 'LoadingFirstPage' ? (
                <>
                    <Skeleton className="h-16 w-full shrink-0" />
                    <Skeleton className="h-16 w-full shrink-0" />
                </>
            ) : sessions.length === 0 ? (
                <p className="py-8 text-center text-sm text-muted-foreground">
                    {t.admin.transcripts.empty}
                </p>
            ) : (
                <ul className="divide-y rounded-md border">
                    {sessions.map((session) => (
                        <li
                            key={session.id}
                            className="flex items-center justify-between gap-2 px-3 py-2"
                        >
                            <div className="min-w-0">
                                <p className="truncate text-sm font-medium">
                                    {session.email ??
                                        t.admin.transcripts.unknownUser}
                                </p>
                                <p className="text-xs text-muted-foreground">
                                    {t.admin.transcripts.started}{' '}
                                    {formatMoment(
                                        session.startedAt,
                                        formatLocale,
                                    )}{' '}
                                    · {session.model}
                                </p>
                            </div>
                            <Link
                                className={buttonVariants({
                                    size: 'sm',
                                    variant: 'outline',
                                })}
                                to={`/admin/transcripts/${encodeURIComponent(session.userId)}/${encodeURIComponent(session.sessionId)}`}
                            >
                                {t.admin.transcripts.open}
                            </Link>
                        </li>
                    ))}
                </ul>
            )}

            {status === 'CanLoadMore' && (
                <Button
                    variant="outline"
                    onClick={() => loadMore(SESSIONS_PAGE_SIZE)}
                >
                    {t.admin.loadMore}
                </Button>
            )}
        </div>
    )
}

type TranscriptLineRow = FunctionReturnType<
    typeof api.v1.admin.queries.getTranscript
>['page'][number]

type Turn = { key: string; role: TranscriptLineRow['role']; text: string }

/**
 * Transcripts are stored as deltas, a few words each. Consecutive lines from the
 * same speaker are one turn; this runs over everything loaded so far, so a turn
 * split across two pages still reads as one.
 */
function toTurns(lines: TranscriptLineRow[]): Turn[] {
    const turns: Turn[] = []
    for (const line of lines) {
        const last = turns.at(-1)
        if (last && last.role === line.role) {
            last.text += line.text
        } else {
            turns.push({ key: line.id, role: line.role, text: line.text })
        }
    }
    return turns
}

export function TranscriptDetail() {
    const t = useT()
    const { userId, sessionId } = useParams()

    return (
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
            <div>
                <Link
                    className={buttonVariants({
                        size: 'sm',
                        variant: 'ghost',
                    })}
                    to="/admin/transcripts"
                >
                    {t.admin.transcripts.back}
                </Link>
            </div>
            {userId && sessionId ? (
                <TranscriptLines userId={userId} sessionId={sessionId} />
            ) : null}
        </div>
    )
}

function TranscriptLines({
    userId,
    sessionId,
}: {
    userId: string
    sessionId: string
}) {
    const t = useT()
    const {
        results: lines,
        status,
        loadMore,
    } = usePaginatedQuery(
        api.v1.admin.queries.getTranscript,
        { userId, sessionId },
        { initialNumItems: EVENTS_PAGE_SIZE },
    )
    const turns = toTurns(lines)

    return (
        <>
            {status === 'LoadingFirstPage' ? (
                <Skeleton className="h-24 w-full shrink-0" />
            ) : turns.length === 0 ? (
                <p className="py-8 text-center text-sm text-muted-foreground">
                    {t.admin.transcripts.noLines}
                </p>
            ) : (
                <div className="flex flex-col gap-2">
                    {turns.map((turn) => (
                        <div
                            key={turn.key}
                            className={cn(
                                'flex max-w-[85%] flex-col gap-1 rounded-lg px-3 py-2 text-sm',
                                turn.role === 'user'
                                    ? 'self-end bg-secondary-container text-on-secondary-container'
                                    : 'self-start bg-muted',
                            )}
                        >
                            <span className="text-xs font-medium opacity-70">
                                {turn.role === 'user'
                                    ? t.admin.transcripts.speakerUser
                                    : t.admin.transcripts.speakerAgent}
                            </span>
                            <p className="whitespace-pre-wrap">{turn.text}</p>
                        </div>
                    ))}
                </div>
            )}

            {status === 'CanLoadMore' && (
                <Button
                    variant="outline"
                    onClick={() => loadMore(EVENTS_PAGE_SIZE)}
                >
                    {t.admin.loadMore}
                </Button>
            )}
        </>
    )
}
