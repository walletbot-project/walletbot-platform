import {
    SCENARIO_2_QUESTIONS,
    SUS_INSTRUCTIONS,
    SUS_STATEMENTS,
    USABILITY_STEPS,
    type UsabilityBlock,
    type UsabilityField,
} from '@wallet-bot/shared'
import { IconButton } from 'actify'
import { useNavigate } from 'react-router-dom'
import { AppBar } from '@/components/m3/app-bar'
import { AssistChip } from '@/components/m3/chip'
import { Icon } from '@/components/m3/icon'
import { type Messages, useT } from '@/lib/i18n'
import {
    ListBlock,
    MaterialBlock,
    NoteBlock,
    SayBlock,
    SectionTitle,
    Surface,
} from './protocol-view'

function stepAnchor(stepId: string): string {
    return `guion-${stepId}`
}

export function UsabilityScript() {
    const t = useT()
    const navigate = useNavigate()

    const jumpTo = (stepId: string) =>
        document
            .getElementById(stepAnchor(stepId))
            ?.scrollIntoView({ behavior: 'smooth', block: 'start' })

    return (
        <>
            <AppBar
                title={t.usability.scriptTitle}
                leading={
                    <IconButton
                        aria-label={t.common.goBack}
                        onPress={() => navigate('/admin/usability')}
                        className="text-on-surface-variant"
                    >
                        <Icon name="arrow_back" />
                    </IconButton>
                }
                actions={
                    <IconButton
                        aria-label={t.usability.printMaterials}
                        onPress={() => navigate('/admin/usability/imprimir')}
                        className="text-on-surface-variant"
                    >
                        <Icon name="print" />
                    </IconButton>
                }
            />
            <div className="min-h-0 flex-1 overflow-y-auto">
                <div className="mx-auto flex w-full max-w-2xl flex-col gap-6 p-4 pb-12">
                    <div className="flex flex-wrap gap-2">
                        {USABILITY_STEPS.map((step, index) => (
                            <AssistChip
                                key={step.id}
                                label={`${index + 1}. ${step.title}`}
                                onPress={() => jumpTo(step.id)}
                            />
                        ))}
                    </div>
                    {USABILITY_STEPS.map((step, index) => (
                        <section
                            key={step.id}
                            id={stepAnchor(step.id)}
                            className="flex scroll-mt-4 flex-col gap-4"
                        >
                            <div className="flex flex-col gap-0.5 px-1">
                                <span className="m3-label-large text-on-surface-variant">
                                    {t.usability.scriptStep({
                                        number: index + 1,
                                    })}
                                </span>
                                <h2 className="m3-headline-small text-on-surface">
                                    {step.title}
                                </h2>
                            </div>
                            {step.blocks.map((block) => (
                                <ScriptBlock
                                    key={scriptBlockKey(block)}
                                    block={block}
                                />
                            ))}
                        </section>
                    ))}
                </div>
            </div>
        </>
    )
}

function scriptBlockKey(block: UsabilityBlock): string {
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

function fieldOptions(field: UsabilityField, t: Messages): string | null {
    switch (field.kind) {
        case 'choice':
        case 'multi':
            return field.options.map((option) => option.label).join(' · ')
        case 'scale':
            return [t.usability.scriptScale, ...(field.hints ?? [])].join(' · ')
        case 'yesNo':
            return `${t.usability.yes} / ${t.usability.no}`
        default:
            return null
    }
}

function FieldSummary({ field }: { field: UsabilityField }) {
    const t = useT()
    const options = fieldOptions(field, t)
    return (
        <li className="flex flex-col gap-0.5">
            <span className="m3-body-medium text-on-surface">
                {field.label}
            </span>
            {field.hint ? (
                <span className="m3-body-small text-on-surface-variant">
                    {field.hint}
                </span>
            ) : null}
            {options ? (
                <span className="m3-body-small text-on-surface-variant">
                    {options}
                </span>
            ) : null}
        </li>
    )
}

function ScriptBlock({ block }: { block: UsabilityBlock }) {
    const t = useT()
    switch (block.type) {
        case 'say':
            return (
                <SayBlock title={block.title} paragraphs={block.paragraphs} />
            )
        case 'note':
            return <NoteBlock text={block.text} />
        case 'list':
            return <ListBlock title={block.title} items={block.items} />
        case 'material':
            return (
                <MaterialBlock
                    title={block.title}
                    materials={block.materials}
                />
            )
        case 'fields':
        case 'checklist':
            return (
                <Surface>
                    {block.title ? (
                        <SectionTitle>{block.title}</SectionTitle>
                    ) : null}
                    <ul className="flex flex-col gap-3">
                        {block.fields.map((field) => (
                            <FieldSummary key={field.key} field={field} />
                        ))}
                    </ul>
                </Surface>
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
                        <p className="m3-body-small text-on-surface-variant">
                            {t.usability.scriptRecord({
                                fields:
                                    block.rows[0]?.fields
                                        .map((field) => field.label)
                                        .join(', ') ?? '',
                            })}
                        </p>
                    </div>
                    {block.rows.map((row) => {
                        const question = SCENARIO_2_QUESTIONS.find(
                            (item) => item.number === row.answer,
                        )
                        return (
                            <Surface key={row.id}>
                                <h3 className="m3-title-small">{row.title}</h3>
                                {row.detail ? (
                                    <p className="m3-body-medium text-on-surface-variant">
                                        {row.detail}
                                    </p>
                                ) : null}
                                {question ? (
                                    <div className="m3-body-small flex flex-col gap-1 rounded-2xl bg-surface-container-highest p-3">
                                        <span>
                                            {t.usability.scriptExpectedAnswer}
                                        </span>
                                        {question.errors ? (
                                            <span className="text-on-surface-variant">
                                                {t.usability.probableErrors}:{' '}
                                                {question.errors}
                                            </span>
                                        ) : null}
                                    </div>
                                ) : null}
                            </Surface>
                        )
                    })}
                </section>
            )
        case 'credentials':
            return (
                <NoteBlock
                    text={t.usability.scriptCredentials({
                        scenario: block.scenario,
                    })}
                />
            )
        case 'scenarioTimer':
            return <NoteBlock text={t.usability.scriptScenarioTimer} />
        case 'sessionTimer':
            return (
                <NoteBlock
                    text={
                        block.action === 'start'
                            ? t.usability.scriptSessionStart
                            : t.usability.scriptSessionEnd
                    }
                />
            )
        case 'sus':
            return (
                <Surface>
                    <SectionTitle>{t.usability.susStatements}</SectionTitle>
                    <p className="m3-body-small text-on-surface-variant">
                        {SUS_INSTRUCTIONS}
                    </p>
                    <ol className="m3-body-medium flex list-decimal flex-col gap-1.5 pl-5">
                        {SUS_STATEMENTS.map((statement) => (
                            <li key={statement}>{statement}</li>
                        ))}
                    </ol>
                </Surface>
            )
        case 'summary':
            return null
        case 'recording':
            return <NoteBlock text={t.usability.scriptRecording} />
    }
}
