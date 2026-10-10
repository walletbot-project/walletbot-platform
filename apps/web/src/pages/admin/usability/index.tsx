import { api } from '@wallet-bot/backend/api'
import { Button, IconButton } from 'actify'
import { usePaginatedQuery } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import type { CSSProperties } from 'react'
import { useNavigate } from 'react-router-dom'
import { AppBar } from '@/components/m3/app-bar'
import { GroupedCard } from '@/components/m3/grouped-card'
import { Icon } from '@/components/m3/icon'
import { StateMessage } from '@/components/m3/state-message'
import { Skeleton } from '@/components/ui/skeleton'
import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import { useFormatLocale, useT } from '@/lib/i18n'
import { participantCode } from './session-data'

const PAGE_SIZE = 20

type SessionRow = FunctionReturnType<
    typeof api.v1.usability.queries.list
>['page'][number]

export function UsabilitySessions() {
    const t = useT()
    const navigate = useNavigate()
    const { results, status, loadMore } = usePaginatedQuery(
        api.v1.usability.queries.list,
        {},
        { initialNumItems: PAGE_SIZE },
    )

    return (
        <>
            <AppBar
                title={t.usability.title}
                leading={
                    <IconButton
                        aria-label={t.common.goBack}
                        onPress={() => navigate('/admin')}
                        className="text-on-surface-variant"
                    >
                        <Icon name="arrow_back" />
                    </IconButton>
                }
                actions={
                    <IconButton
                        aria-label={t.usability.newSession}
                        onPress={() => navigate('/admin/usability/new')}
                        className="text-on-surface-variant"
                    >
                        <Icon name="add" />
                    </IconButton>
                }
            />
            <div className="flex min-h-0 flex-1 flex-col overflow-y-auto">
                {status === 'LoadingFirstPage' ? (
                    <div className="mx-auto flex w-full max-w-2xl flex-col gap-2 p-4">
                        <Skeleton className="h-16 w-full" />
                        <Skeleton className="h-16 w-full" />
                        <Skeleton className="h-16 w-full" />
                    </div>
                ) : results.length === 0 ? (
                    <StateMessage
                        icon="science"
                        title={t.usability.empty}
                        detail={t.usability.emptyDetail}
                        action={
                            <Button
                                variant="filled"
                                onPress={() => navigate('/admin/usability/new')}
                            >
                                <Icon name="add" size={18} />
                                {t.usability.newSession}
                            </Button>
                        }
                    />
                ) : (
                    <div className="mx-auto flex w-full max-w-2xl flex-col gap-4 p-4">
                        <div
                            className="flex flex-col"
                            style={{ gap: GROUP_SPACING }}
                        >
                            {results.map((session, index) => (
                                <SessionTile
                                    key={session.id}
                                    session={session}
                                    radius={groupedRadius(
                                        index,
                                        results.length,
                                    )}
                                    onOpen={() =>
                                        navigate(
                                            `/admin/usability/${session.id}`,
                                        )
                                    }
                                />
                            ))}
                        </div>
                        {status === 'CanLoadMore' ? (
                            <Button
                                variant="outlined"
                                onPress={() => loadMore(PAGE_SIZE)}
                            >
                                {t.usability.loadMore}
                            </Button>
                        ) : null}
                    </div>
                )}
            </div>
        </>
    )
}

function SessionTile({
    session,
    radius,
    onOpen,
}: {
    session: SessionRow
    radius: CSSProperties
    onOpen: () => void
}) {
    const t = useT()
    const locale = useFormatLocale()
    const [year, month, day] = session.sessionDay.split('-').map(Number)
    const date = new Date(year, month - 1, day).toLocaleDateString(locale, {
        dateStyle: 'medium',
    })
    const status =
        session.status === 'ready'
            ? t.usability.statusReady
            : session.status === 'failed'
              ? t.usability.statusFailed
              : t.usability.statusProvisioning

    return (
        <GroupedCard radius={radius} onClick={onOpen}>
            <div className="flex items-center gap-4 px-4 py-3">
                <span className="m3-title-medium flex size-12 shrink-0 items-center justify-center rounded-full bg-secondary-container text-on-secondary-container">
                    {participantCode(session.number)}
                </span>
                <div className="flex min-w-0 flex-1 flex-col">
                    <span className="m3-body-large">
                        {t.usability.groupLabel({ group: session.group })} ·{' '}
                        {date}
                    </span>
                    <span
                        className={
                            session.status === 'failed'
                                ? 'm3-body-medium text-error'
                                : 'm3-body-medium text-on-surface-variant'
                        }
                    >
                        {status}
                        {session.hasRecording
                            ? ` · ${t.usability.hasRecording}`
                            : ''}
                    </span>
                </div>
                <Icon
                    name="chevron_right"
                    className="text-on-surface-variant"
                />
            </div>
        </GroupedCard>
    )
}
