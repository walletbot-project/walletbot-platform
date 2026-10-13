import {
    SESSION_END_KEY,
    SESSION_START_KEY,
    scenarioEndKey,
    scenarioStartKey,
    USABILITY_STEPS,
    type UsabilityStep,
} from '@wallet-bot/shared'
import { Button, IconButton } from 'actify'
import { type ReactNode, useEffect, useRef } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
import { StateMessage } from '@/components/m3/state-message'
import { useT } from '@/lib/i18n'
import { LiveElapsed, StepBlocks } from './blocks'
import { SessionLoading, SessionNotFound } from './session'
import {
    formatElapsed,
    numberValue,
    type UsabilitySession,
    useFieldValues,
    useSessionFromUrl,
    useSessionWrites,
} from './session-data'

export function UsabilitySessionStep() {
    const t = useT()
    const navigate = useNavigate()
    const { stepId } = useParams()
    const { session, sessionId } = useSessionFromUrl()
    const index = USABILITY_STEPS.findIndex((step) => step.id === stepId)
    const step = index === -1 ? undefined : USABILITY_STEPS[index]

    const back = (
        <IconButton
            aria-label={t.common.goBack}
            onPress={() => navigate(`/admin/usability/${sessionId}`)}
            className="text-on-surface-variant"
        >
            <Icon name="arrow_back" />
        </IconButton>
    )

    if (session === undefined) {
        return (
            <>
                <AppBar title={step?.title} leading={back} />
                <SessionLoading />
            </>
        )
    }
    if (session === null) {
        return (
            <>
                <AppBar leading={back} />
                <SessionNotFound />
            </>
        )
    }
    if (!step) {
        return (
            <>
                <AppBar leading={back} />
                <StateMessage
                    icon="search_off"
                    title={t.usability.stepNotFound}
                    action={
                        <Button
                            variant="filled"
                            onPress={() =>
                                navigate(`/admin/usability/${session.id}`)
                            }
                        >
                            {t.usability.finish}
                        </Button>
                    }
                />
            </>
        )
    }

    const previous = USABILITY_STEPS[index - 1]
    const next = USABILITY_STEPS[index + 1]

    return (
        <>
            <AppBar
                title={step.title}
                leading={back}
                actions={<SessionClock session={session} />}
            />
            <StepBody key={step.id}>
                <div className="flex flex-col gap-2 px-1">
                    <span className="m3-label-large text-on-surface-variant">
                        {t.usability.stepOf({
                            current: index + 1,
                            total: USABILITY_STEPS.length,
                        })}
                    </span>
                    <div className="h-1 w-full overflow-hidden rounded-full bg-surface-container-highest">
                        <div
                            className="h-full rounded-full bg-secondary"
                            style={{
                                width: `${((index + 1) / USABILITY_STEPS.length) * 100}%`,
                            }}
                        />
                    </div>
                </div>
                <StepContent session={session} blocks={step.blocks} />
            </StepBody>
            <StepFooter
                session={session}
                step={step}
                previous={previous}
                next={next}
            />
        </>
    )
}

function StepFooter({
    session,
    step,
    previous,
    next,
}: {
    session: UsabilitySession
    step: UsabilityStep
    previous: UsabilityStep | undefined
    next: UsabilityStep | undefined
}) {
    const t = useT()
    const navigate = useNavigate()
    const values = useFieldValues(session)
    const { stamp } = useSessionWrites(session.id)

    const goForward = () => {
        for (const block of step.blocks) {
            if (block.type !== 'scenarioTimer') continue
            const endKey = scenarioEndKey(block.scenario)
            const running =
                numberValue(values, scenarioStartKey(block.scenario)) !==
                    undefined && numberValue(values, endKey) === undefined
            if (running) stamp(endKey)
        }
        navigate(
            next
                ? `/admin/usability/${session.id}/${next.id}`
                : `/admin/usability/${session.id}`,
        )
    }

    return (
        <footer className="shrink-0 border-t border-outline-variant bg-surface">
            <div className="mx-auto flex w-full max-w-2xl gap-2 p-3">
                <Button
                    variant="outlined"
                    className="flex-1"
                    isDisabled={!previous}
                    onPress={() =>
                        previous &&
                        navigate(
                            `/admin/usability/${session.id}/${previous.id}`,
                        )
                    }
                >
                    <Icon name="arrow_back" size={18} />
                    {t.usability.previous}
                </Button>
                <Button variant="filled" className="flex-1" onPress={goForward}>
                    {next ? t.usability.next : t.usability.finish}
                    <Icon name={next ? 'arrow_forward' : 'check'} size={18} />
                </Button>
            </div>
        </footer>
    )
}

/** Scrolls back to the top whenever the step changes; `key` remounts it. */
function StepBody({ children }: { children: ReactNode }) {
    const scroller = useRef<HTMLDivElement>(null)
    useEffect(() => {
        scroller.current?.scrollTo({ top: 0 })
    }, [])
    return (
        <div ref={scroller} className="min-h-0 flex-1 overflow-y-auto">
            <div className="mx-auto flex w-full max-w-2xl flex-col gap-4 p-4 pb-8">
                {children}
            </div>
        </div>
    )
}

function StepContent({
    session,
    blocks,
}: {
    session: UsabilitySession
    blocks: (typeof USABILITY_STEPS)[number]['blocks']
}) {
    const values = useFieldValues(session)
    const { save, stamp } = useSessionWrites(session.id)
    return (
        <StepBlocks
            blocks={blocks}
            context={{ session, values, save, stamp }}
        />
    )
}

function SessionClock({ session }: { session: UsabilitySession }) {
    const t = useT()
    const values = useFieldValues(session)
    const startedAt = numberValue(values, SESSION_START_KEY)
    const endedAt = numberValue(values, SESSION_END_KEY)
    if (startedAt === undefined) return null
    return (
        <span
            className="m3-title-medium mr-3 inline-flex items-center gap-1 tabular-nums text-on-surface-variant"
            title={t.usability.sessionTime}
        >
            <Icon name="timer" size={20} />
            {endedAt === undefined ? (
                <LiveElapsed since={startedAt} />
            ) : (
                formatElapsed(endedAt - startedAt)
            )}
        </span>
    )
}
