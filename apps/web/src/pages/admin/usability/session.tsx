import { api } from '@wallet-bot/backend/api'
import {
    SESSION_END_KEY,
    SESSION_START_KEY,
    USABILITY_SCENARIOS,
    USABILITY_STEPS,
} from '@wallet-bot/shared'
import { Button, CircularProgress, IconButton } from 'actify'
import { useMutation } from 'convex/react'
import type { ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { AppBar } from '@/components/m3/app-bar'
import { GroupedCard } from '@/components/m3/grouped-card'
import { Icon } from '@/components/m3/icon'
import { StateMessage } from '@/components/m3/state-message'
import { Skeleton } from '@/components/ui/skeleton'
import { useToastMutation } from '@/hooks/use-toast-mutation'
import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import { useFormatLocale, useT } from '@/lib/i18n'
import { CredentialsBlock } from './blocks'
import {
    formatClock,
    formatElapsed,
    numberValue,
    participantCode,
    stepProgress,
    type UsabilitySession,
    useFieldValues,
    useSessionFromUrl,
} from './session-data'

export function SessionNotFound() {
    const t = useT()
    const navigate = useNavigate()
    return (
        <StateMessage
            icon="search_off"
            title={t.usability.notFound}
            action={
                <Button
                    variant="filled"
                    onPress={() => navigate('/admin/usability')}
                >
                    {t.usability.backToList}
                </Button>
            }
        />
    )
}

export function SessionLoading() {
    return (
        <div className="mx-auto flex w-full max-w-2xl flex-col gap-4 p-4">
            <Skeleton className="h-24 w-full" />
            <Skeleton className="h-40 w-full" />
            <Skeleton className="h-64 w-full" />
        </div>
    )
}

export function UsabilitySessionOverview() {
    const t = useT()
    const navigate = useNavigate()
    const { session } = useSessionFromUrl()

    const backToList = (
        <IconButton
            aria-label={t.common.goBack}
            onPress={() => navigate('/admin/usability')}
            className="text-on-surface-variant"
        >
            <Icon name="arrow_back" />
        </IconButton>
    )

    if (session === undefined || session === null) {
        return (
            <>
                <AppBar title={t.usability.title} leading={backToList} />
                {session === undefined ? (
                    <SessionLoading />
                ) : (
                    <SessionNotFound />
                )}
            </>
        )
    }

    return (
        <>
            <AppBar
                title={participantCode(session.number)}
                leading={backToList}
            />
            <div className="min-h-0 flex-1 overflow-y-auto">
                <div className="mx-auto flex w-full max-w-2xl flex-col gap-4 p-4 pb-8">
                    <ProvisioningStatus session={session} />
                    <SessionDetails session={session} />
                    <Button
                        variant="filled"
                        onPress={() =>
                            navigate(
                                `/admin/usability/${session.id}/${USABILITY_STEPS[0].id}`,
                            )
                        }
                    >
                        <Icon name="play_arrow" size={18} />
                        {t.usability.openAssistant}
                    </Button>
                    <StepList session={session} />
                    <h2 className="m3-title-medium px-1 pt-2">
                        {t.usability.credentials}
                    </h2>
                    {USABILITY_SCENARIOS.map((scenario) => (
                        <CredentialsBlock
                            key={scenario}
                            session={session}
                            scenario={scenario}
                        />
                    ))}
                </div>
            </div>
        </>
    )
}

function Card({ children }: { children: ReactNode }) {
    return (
        <section className="flex flex-col gap-3 rounded-3xl bg-surface-container-high p-4 text-on-surface">
            {children}
        </section>
    )
}

function ProvisioningStatus({ session }: { session: UsabilitySession }) {
    const t = useT()
    const retry = useMutation(api.v1.usability.mutations.retryProvisioning)
    const { pending, run } = useToastMutation()

    if (session.status === 'ready') return null
    if (session.status === 'provisioning') {
        return (
            <Card>
                <div className="flex items-center gap-3">
                    <CircularProgress
                        isIndeterminate
                        size="md"
                        aria-label={t.usability.provisioningTitle}
                    />
                    <div className="flex flex-col">
                        <span className="m3-title-small">
                            {t.usability.provisioningTitle}
                        </span>
                        <span className="m3-body-medium text-on-surface-variant">
                            {t.usability.provisioningDetail}
                        </span>
                    </div>
                </div>
            </Card>
        )
    }
    return (
        <Card>
            <div className="flex items-start gap-3">
                <Icon name="error" className="text-error" />
                <div className="flex min-w-0 flex-col gap-1">
                    <span className="m3-title-small">
                        {t.usability.failedTitle}
                    </span>
                    {session.error ? (
                        <span className="m3-body-small break-words text-on-surface-variant">
                            {session.error}
                        </span>
                    ) : null}
                </div>
            </div>
            <div>
                <Button
                    variant="tonal"
                    isDisabled={pending}
                    onPress={() =>
                        void run(retry({ sessionId: session.id }), {
                            loading: t.usability.retrying,
                            success: t.usability.retried,
                            error: t.usability.retryFailed,
                        })
                    }
                >
                    <Icon name="refresh" size={18} />
                    {t.usability.retry}
                </Button>
            </div>
        </Card>
    )
}

function SessionDetails({ session }: { session: UsabilitySession }) {
    const t = useT()
    const locale = useFormatLocale()
    const values = useFieldValues(session)
    const startedAt = numberValue(values, SESSION_START_KEY)
    const endedAt = numberValue(values, SESSION_END_KEY)
    const [year, month, day] = session.sessionDay.split('-').map(Number)
    const rows: [string, string][] = [
        [t.usability.group, t.usability.groupLabel({ group: session.group })],
        [
            t.usability.sessionDay,
            new Date(year, month - 1, day).toLocaleDateString(locale, {
                dateStyle: 'long',
            }),
        ],
        [
            t.usability.started,
            startedAt === undefined
                ? t.usability.notStarted
                : formatClock(startedAt, locale),
        ],
        [
            t.usability.ended,
            endedAt === undefined
                ? t.usability.noValue
                : formatClock(endedAt, locale),
        ],
        [
            t.usability.duration,
            startedAt !== undefined && endedAt !== undefined
                ? formatElapsed(endedAt - startedAt)
                : t.usability.noValue,
        ],
    ]
    return (
        <Card>
            <dl className="m3-body-medium grid grid-cols-[auto_1fr] gap-x-4 gap-y-2">
                {rows.map(([label, value]) => (
                    <div key={label} className="contents">
                        <dt className="text-on-surface-variant">{label}</dt>
                        <dd>{value}</dd>
                    </div>
                ))}
            </dl>
        </Card>
    )
}

function StepList({ session }: { session: UsabilitySession }) {
    const t = useT()
    const navigate = useNavigate()
    const values = useFieldValues(session)
    return (
        <div className="flex flex-col" style={{ gap: GROUP_SPACING }}>
            {USABILITY_STEPS.map((step, index) => {
                const progress = stepProgress(step, values)
                const complete =
                    progress.total > 0 && progress.done === progress.total
                return (
                    <GroupedCard
                        key={step.id}
                        radius={groupedRadius(index, USABILITY_STEPS.length)}
                        onClick={() =>
                            navigate(
                                `/admin/usability/${session.id}/${step.id}`,
                            )
                        }
                    >
                        <div className="flex items-center gap-4 px-4 py-3">
                            <span className="m3-label-large flex size-8 shrink-0 items-center justify-center rounded-full bg-secondary-container text-on-secondary-container">
                                {complete ? (
                                    <Icon name="check" size={18} />
                                ) : (
                                    index + 1
                                )}
                            </span>
                            <div className="flex min-w-0 flex-1 flex-col">
                                <span className="m3-body-large">
                                    {step.title}
                                </span>
                                {progress.total > 0 ? (
                                    <span className="m3-body-small text-on-surface-variant">
                                        {t.usability.stepProgress(progress)}
                                    </span>
                                ) : null}
                            </div>
                            <Icon
                                name="chevron_right"
                                className="text-on-surface-variant"
                            />
                        </div>
                    </GroupedCard>
                )
            })}
        </div>
    )
}
