import {
    SCENARIO_2_QUESTIONS,
    SESSION_END_KEY,
    SESSION_START_KEY,
    SUS_STATEMENTS,
    scenario2ExpectedAnswer,
    scenarioDifficultyKey,
    scenarioEndKey,
    scenarioStartKey,
    susKey,
    susScore,
    USABILITY_FIELDS,
    USABILITY_SCENARIOS,
    USABILITY_STEPS,
    type UsabilityBlock,
    type UsabilityFieldValue,
    type UsabilityRow,
    type UsabilityScenario,
} from '@wallet-bot/shared'
import { Button } from 'actify'
import { toast } from 'sonner'
import { Icon } from '@/components/m3/icon'
import { useFormatLocale, useT } from '@/lib/i18n'
import { FieldInput } from './field-input'
import {
    ListBlock,
    MaterialBlock,
    NoteBlock,
    SayBlock,
    SectionTitle,
    Surface,
} from './protocol-view'
import { RecordingBlock } from './recording'
import {
    type FieldValues,
    filledText,
    formatClock,
    formatElapsed,
    numberValue,
    type UsabilitySession,
    useNow,
} from './session-data'

type BlockContext = {
    session: UsabilitySession
    values: FieldValues
    save: (key: string, value: UsabilityFieldValue) => void
    stamp: (key: string) => void
}

export function StepBlocks({
    blocks,
    context,
}: {
    blocks: readonly UsabilityBlock[]
    context: BlockContext
}) {
    return (
        <div className="flex flex-col gap-4">
            {blocks.map((block) => (
                <Block key={blockKey(block)} block={block} context={context} />
            ))}
        </div>
    )
}

function blockKey(block: UsabilityBlock): string {
    switch (block.type) {
        case 'say':
            return `say-${block.paragraphs[0]}`
        case 'note':
            return `note-${block.text}`
        case 'list':
        case 'material':
        case 'rows':
        case 'checklist':
            return `${block.type}-${block.title}`
        case 'fields':
            return `fields-${block.fields[0]?.key}`
        case 'credentials':
        case 'scenarioTimer':
            return `${block.type}-${block.scenario}`
        case 'sessionTimer':
            return `sessionTimer-${block.action}`
        case 'sus':
        case 'summary':
        case 'recording':
            return block.type
    }
}

function Block({
    block,
    context,
}: {
    block: UsabilityBlock
    context: BlockContext
}) {
    switch (block.type) {
        case 'say':
            return (
                <SayBlock title={block.title} paragraphs={block.paragraphs} />
            )
        case 'note':
            return <NoteBlock text={block.text} />
        case 'list':
            return <ListBlock title={block.title} items={block.items} />
        case 'fields':
            return (
                <Surface>
                    {block.title ? (
                        <SectionTitle>{block.title}</SectionTitle>
                    ) : null}
                    <div className="flex flex-col gap-5">
                        {block.fields.map((field) => (
                            <FieldInput
                                key={field.key}
                                field={field}
                                value={context.values.get(field.key)}
                                onSave={context.save}
                                onStamp={context.stamp}
                            />
                        ))}
                    </div>
                </Surface>
            )
        case 'checklist':
            return (
                <Surface>
                    <SectionTitle>{block.title}</SectionTitle>
                    <div className="flex flex-col gap-2">
                        {block.fields.map((field) => (
                            <FieldInput
                                key={field.key}
                                field={field}
                                value={context.values.get(field.key)}
                                onSave={context.save}
                                onStamp={context.stamp}
                            />
                        ))}
                    </div>
                </Surface>
            )
        case 'material':
            return (
                <MaterialBlock
                    title={block.title}
                    materials={block.materials}
                />
            )
        case 'rows':
            return (
                <section className="flex flex-col gap-3">
                    <div className="flex flex-col gap-1 px-1">
                        <SectionTitle>{block.title}</SectionTitle>
                        {block.legend ? (
                            <p className="m3-body-small text-on-surface-variant">
                                {block.legend}
                            </p>
                        ) : null}
                    </div>
                    {block.rows.map((row) => (
                        <RowCard key={row.id} row={row} context={context} />
                    ))}
                </section>
            )
        case 'credentials':
            return (
                <CredentialsBlock
                    session={context.session}
                    scenario={block.scenario}
                />
            )
        case 'scenarioTimer':
            return <ScenarioTimer scenario={block.scenario} context={context} />
        case 'sessionTimer':
            return <SessionTimer action={block.action} context={context} />
        case 'sus':
            return <SusBlock context={context} />
        case 'summary':
            return <SummaryBlock context={context} />
        case 'recording':
            return (
                <RecordingBlock
                    session={context.session}
                    values={context.values}
                />
            )
    }
}

function RowCard({
    row,
    context,
}: {
    row: UsabilityRow
    context: BlockContext
}) {
    const t = useT()
    const answers = context.session.scenario2Answers
    const question = SCENARIO_2_QUESTIONS.find(
        (item) => item.number === row.answer,
    )
    return (
        <Surface>
            <div className="flex flex-col gap-1">
                <h3 className="m3-title-small">{row.title}</h3>
                {row.detail ? (
                    <p className="m3-body-medium text-on-surface-variant">
                        {row.detail}
                    </p>
                ) : null}
            </div>
            {row.answer !== undefined ? (
                <div className="flex flex-col gap-1 rounded-2xl bg-surface-container-highest p-3">
                    <span className="m3-label-medium text-on-surface-variant">
                        {t.usability.expectedAnswer}
                    </span>
                    <span className="m3-body-medium">
                        {answers
                            ? scenario2ExpectedAnswer(row.answer, answers)
                            : t.usability.answersPending}
                    </span>
                    {question?.errors ? (
                        <>
                            <span className="m3-label-medium mt-1 text-on-surface-variant">
                                {t.usability.probableErrors}
                            </span>
                            <span className="m3-body-small">
                                {question.errors}
                            </span>
                        </>
                    ) : null}
                </div>
            ) : null}
            <div className="flex flex-col gap-4">
                {row.fields.map((field) => (
                    <FieldInput
                        key={field.key}
                        field={field}
                        value={context.values.get(field.key)}
                        onSave={context.save}
                        onStamp={context.stamp}
                    />
                ))}
            </div>
        </Surface>
    )
}

function CopyRow({ label, value }: { label: string; value: string }) {
    const t = useT()
    const copy = () => {
        navigator.clipboard
            .writeText(value)
            .then(() => toast.success(t.usability.copied))
            .catch(() => toast.error(t.usability.copyFailed))
    }
    return (
        <div className="flex items-center gap-2">
            <div className="flex min-w-0 flex-1 flex-col">
                <span className="m3-label-medium text-on-surface-variant">
                    {label}
                </span>
                <span className="m3-body-large break-all font-mono">
                    {value}
                </span>
            </div>
            <button
                type="button"
                aria-label={t.usability.copy}
                onClick={copy}
                className="m3-state-layer flex size-10 shrink-0 cursor-pointer items-center justify-center rounded-full text-on-surface-variant"
            >
                <Icon name="content_copy" size={20} />
            </button>
        </div>
    )
}

export function CredentialsBlock({
    session,
    scenario,
}: {
    session: UsabilitySession
    scenario: UsabilityScenario
}) {
    const t = useT()
    const user = session.users.find((item) => item.scenario === scenario)
    return (
        <Surface>
            <SectionTitle>
                {t.usability.scenarioUser({ scenario })}
            </SectionTitle>
            {user ? (
                <div className="flex flex-col gap-2">
                    <CopyRow label={t.usability.email} value={user.email} />
                    <CopyRow
                        label={t.usability.password}
                        value={session.password}
                    />
                </div>
            ) : (
                <p className="m3-body-medium text-on-surface-variant">
                    {session.status === 'failed'
                        ? t.usability.userFailed
                        : t.usability.userPending}
                </p>
            )}
        </Surface>
    )
}

function TimerReadout({
    startedAt,
    endedAt,
}: {
    startedAt: number | undefined
    endedAt: number | undefined
}) {
    const t = useT()
    const locale = useFormatLocale()
    const running = startedAt !== undefined && endedAt === undefined
    return (
        <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1">
            <span className="m3-display-small tabular-nums">
                {startedAt === undefined ? (
                    formatElapsed(0)
                ) : running ? (
                    <LiveElapsed since={startedAt} />
                ) : (
                    formatElapsed((endedAt ?? startedAt) - startedAt)
                )}
            </span>
            <span className="m3-body-medium text-on-surface-variant">
                {startedAt === undefined
                    ? t.usability.notStarted
                    : endedAt === undefined
                      ? t.usability.startedAt({
                            time: formatClock(startedAt, locale),
                        })
                      : t.usability.startedAndEnded({
                            start: formatClock(startedAt, locale),
                            end: formatClock(endedAt, locale),
                        })}
            </span>
        </div>
    )
}

export function LiveElapsed({ since }: { since: number }) {
    const now = useNow(1000)
    return <>{formatElapsed(now - since)}</>
}

function ScenarioTimer({
    scenario,
    context,
}: {
    scenario: UsabilityScenario
    context: BlockContext
}) {
    const t = useT()
    const startKey = scenarioStartKey(scenario)
    const endKey = scenarioEndKey(scenario)
    const startedAt = numberValue(context.values, startKey)
    const endedAt = numberValue(context.values, endKey)
    return (
        <Surface>
            <SectionTitle>
                {t.usability.scenarioTimer({ scenario })}
            </SectionTitle>
            <TimerReadout startedAt={startedAt} endedAt={endedAt} />
            <div className="flex flex-wrap gap-2">
                {startedAt === undefined ? (
                    <Button
                        variant="filled"
                        onPress={() => context.stamp(startKey)}
                    >
                        <Icon name="play_arrow" size={18} />
                        {t.usability.startScenario}
                    </Button>
                ) : endedAt === undefined ? (
                    <Button
                        variant="filled"
                        onPress={() => context.stamp(endKey)}
                    >
                        <Icon name="stop" size={18} />
                        {t.usability.endScenario}
                    </Button>
                ) : null}
                {startedAt !== undefined ? (
                    <Button
                        variant="text"
                        onPress={() => {
                            context.save(startKey, null)
                            context.save(endKey, null)
                        }}
                    >
                        {t.usability.resetTimer}
                    </Button>
                ) : null}
            </div>
        </Surface>
    )
}

function SessionTimer({
    action,
    context,
}: {
    action: 'start' | 'end'
    context: BlockContext
}) {
    const t = useT()
    const startedAt = numberValue(context.values, SESSION_START_KEY)
    const endedAt = numberValue(context.values, SESSION_END_KEY)
    const canPress =
        action === 'start'
            ? startedAt === undefined
            : startedAt !== undefined && endedAt === undefined
    return (
        <Surface>
            <SectionTitle>{t.usability.sessionTime}</SectionTitle>
            <TimerReadout startedAt={startedAt} endedAt={endedAt} />
            {canPress ? (
                <div>
                    <Button
                        variant="filled"
                        onPress={() =>
                            context.stamp(
                                action === 'start'
                                    ? SESSION_START_KEY
                                    : SESSION_END_KEY,
                            )
                        }
                    >
                        <Icon
                            name={action === 'start' ? 'play_arrow' : 'stop'}
                            size={18}
                        />
                        {action === 'start'
                            ? t.usability.startSession
                            : t.usability.endSession}
                    </Button>
                </div>
            ) : null}
        </Surface>
    )
}

function susAnswers(values: FieldValues): (number | undefined)[] {
    return SUS_STATEMENTS.map((_, index) => numberValue(values, susKey(index)))
}

function SusBlock({ context }: { context: BlockContext }) {
    const t = useT()
    const score = susScore(susAnswers(context.values))
    return (
        <>
            <Surface>
                <SectionTitle>{t.usability.susScore}</SectionTitle>
                <span className="m3-display-small tabular-nums">
                    {score === null ? t.usability.noValue : score}
                </span>
                <p className="m3-body-small text-on-surface-variant">
                    {score === null
                        ? t.usability.susPending
                        : t.usability.susReference}
                </p>
            </Surface>
            <Surface>
                <div className="flex flex-col gap-5">
                    {SUS_STATEMENTS.map((_, index) => {
                        const field = USABILITY_FIELDS.get(susKey(index))
                        if (!field) return null
                        return (
                            <FieldInput
                                key={field.key}
                                field={field}
                                value={context.values.get(field.key)}
                                onSave={context.save}
                                onStamp={context.stamp}
                            />
                        )
                    })}
                </div>
            </Surface>
        </>
    )
}

type HintNote = { where: string; text: string }

function collectHints(values: FieldValues): HintNote[] {
    const hints: HintNote[] = []
    for (const step of USABILITY_STEPS) {
        for (const block of step.blocks) {
            if (block.type !== 'rows') continue
            for (const row of block.rows) {
                for (const field of row.fields) {
                    if (!field.key.endsWith('.pista')) continue
                    const text = filledText(values.get(field.key))
                    if (text) {
                        hints.push({
                            where: `${step.title} · ${row.title}`,
                            text,
                        })
                    }
                }
            }
        }
    }
    return hints
}

function SummaryBlock({ context }: { context: BlockContext }) {
    const t = useT()
    const score = susScore(susAnswers(context.values))
    const hints = collectHints(context.values)
    return (
        <Surface>
            <SectionTitle>{t.usability.summaryTitle}</SectionTitle>
            <dl className="m3-body-medium grid grid-cols-[1fr_auto] gap-x-4 gap-y-2">
                {USABILITY_SCENARIOS.map((scenario) => (
                    <SummaryRow
                        key={scenario}
                        label={t.usability.difficulty({ scenario })}
                        value={numberValue(
                            context.values,
                            scenarioDifficultyKey(scenario),
                        )}
                    />
                ))}
                <SummaryRow
                    label={t.usability.susScore}
                    value={score ?? undefined}
                />
            </dl>
            <div className="flex flex-col gap-1">
                <span className="m3-label-large text-on-surface-variant">
                    {t.usability.hintsGiven}
                </span>
                {hints.length === 0 ? (
                    <p className="m3-body-medium text-on-surface-variant">
                        {t.usability.noHints}
                    </p>
                ) : (
                    <ul className="m3-body-medium flex flex-col gap-1.5">
                        {hints.map((hint) => (
                            <li key={`${hint.where}-${hint.text}`}>
                                <span className="text-on-surface-variant">
                                    {hint.where}:
                                </span>{' '}
                                {hint.text}
                            </li>
                        ))}
                    </ul>
                )}
            </div>
        </Surface>
    )
}

function SummaryRow({
    label,
    value,
}: {
    label: string
    value: number | undefined
}) {
    const t = useT()
    return (
        <>
            <dt className="text-on-surface-variant">{label}</dt>
            <dd className="tabular-nums">{value ?? t.usability.noValue}</dd>
        </>
    )
}
