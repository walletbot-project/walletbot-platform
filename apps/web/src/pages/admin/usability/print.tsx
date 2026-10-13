import {
    OBSERVATION_SHEET_CLOSING,
    OBSERVATION_SHEET_DATA,
    USABILITY_PRINT_TEXT as P,
    SCENARIO_0_EXPENSE_LIST,
    SCENARIO_1_STATEMENT,
    SCENARIO_1_TICKETS,
    SCENARIO_2_QUESTIONS,
    SUS_INSTRUCTIONS,
    SUS_STATEMENTS,
    USABILITY_STEPS,
    type UsabilityBlock,
    type UsabilityMaterial,
} from '@wallet-bot/shared'
import { Button, IconButton } from 'actify'
import type { ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { useNavigate } from 'react-router-dom'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
import { useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'

// Only the portal copy prints: the app shell (#root) is hidden on paper.
const PRINT_CSS = `@media print {
    #root { display: none !important; }
    html, body { background: #fff !important; }
    @page { size: A4; margin: 12mm; }
}`

const CARDS_PER_PAGE = 4

type RowsBlock = Extract<UsabilityBlock, { type: 'rows' }>

function rowsOf(stepId: string): RowsBlock | undefined {
    const step = USABILITY_STEPS.find((item) => item.id === stepId)
    return step?.blocks.find(
        (block): block is RowsBlock => block.type === 'rows',
    )
}

function assistantQuestions(): string[] {
    const step = USABILITY_STEPS.find((item) => item.id === 'asistente')
    return (step?.blocks ?? []).flatMap((block) =>
        block.type === 'fields' ? block.fields.map((field) => field.label) : [],
    )
}

export function UsabilityPrint() {
    const t = useT()
    const navigate = useNavigate()
    const print = () => window.print()

    return (
        <>
            <AppBar
                title={t.usability.printTitle}
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
                        aria-label={t.usability.print}
                        onPress={print}
                        className="text-on-surface-variant"
                    >
                        <Icon name="print" />
                    </IconButton>
                }
            />
            <div className="min-h-0 flex-1 overflow-y-auto bg-surface-container">
                <div className="mx-auto flex w-full max-w-[52rem] flex-col gap-4 p-4 pb-12">
                    <div className="flex flex-col gap-3 rounded-3xl bg-surface-container-high p-4 text-on-surface">
                        <p className="m3-body-medium">
                            {t.usability.printHint}
                        </p>
                        <div>
                            <Button variant="filled" onPress={print}>
                                <Icon name="print" size={18} />
                                {t.usability.print}
                            </Button>
                        </div>
                    </div>
                    <PrintSheets preview />
                </div>
            </div>
            {createPortal(
                <div className="hidden print:block">
                    <style>{PRINT_CSS}</style>
                    <PrintSheets preview={false} />
                </div>,
                document.body,
            )}
        </>
    )
}

function Sheet({
    preview,
    label,
    children,
}: {
    preview: boolean
    label: string
    children: ReactNode
}) {
    return (
        <article
            className={cn(
                'flex flex-col gap-4 bg-white text-black',
                preview
                    ? 'rounded-2xl p-5 shadow-sm sm:p-10'
                    : 'not-last:break-after-page',
            )}
        >
            <span className="text-xs tracking-wide text-black/60 uppercase">
                {label}
            </span>
            {children}
        </article>
    )
}

function MaterialTable({
    material,
    dense = false,
}: {
    material: Extract<UsabilityMaterial, { kind: 'table' }>
    dense?: boolean
}) {
    const align = (index: number) =>
        material.amountColumns?.includes(index) ? 'text-right' : 'text-left'
    const cell = dense ? 'px-1.5 py-1' : 'px-2 py-1.5'
    return (
        <div className="overflow-x-auto">
            <table className="w-full border-collapse text-sm">
                <thead>
                    <tr className="border-y-2 border-black">
                        {material.columns.map((column, index) => (
                            <th
                                key={column}
                                className={cn(
                                    cell,
                                    'font-semibold',
                                    align(index),
                                )}
                            >
                                {column}
                            </th>
                        ))}
                    </tr>
                </thead>
                <tbody>
                    {material.rows.map((row) => (
                        <tr
                            key={row.join('|')}
                            className="border-b border-black/20"
                        >
                            {row.map((value, index) => (
                                <td
                                    key={material.columns[index]}
                                    className={cn(
                                        cell,
                                        'tabular-nums whitespace-nowrap',
                                        align(index),
                                    )}
                                >
                                    {value}
                                </td>
                            ))}
                        </tr>
                    ))}
                    {material.total ? (
                        <tr className="border-t-2 border-black">
                            {material.total.map((value, index) => (
                                <td
                                    key={material.columns[index]}
                                    className={cn(
                                        cell,
                                        'font-semibold tabular-nums',
                                        align(index),
                                    )}
                                >
                                    {value}
                                </td>
                            ))}
                        </tr>
                    ) : null}
                </tbody>
            </table>
        </div>
    )
}

function BlankTable({
    columns,
    rows,
    firstColumnClass,
}: {
    columns: readonly string[]
    rows: readonly string[]
    firstColumnClass?: string
}) {
    return (
        <div className="overflow-x-auto">
            <table className="w-full min-w-[34rem] table-fixed border-collapse text-xs break-inside-avoid">
                <thead>
                    <tr>
                        {columns.map((column, index) => (
                            <th
                                key={column}
                                className={cn(
                                    'border border-black/50 bg-black/5 px-1.5 py-1 text-left font-semibold',
                                    index === 0 ? firstColumnClass : undefined,
                                )}
                            >
                                {column}
                            </th>
                        ))}
                    </tr>
                </thead>
                <tbody>
                    {rows.map((row) => (
                        <tr key={row}>
                            <td className="h-10 border border-black/50 px-1.5 align-top">
                                {row}
                            </td>
                            {columns.slice(1).map((column) => (
                                <td
                                    key={column}
                                    className="h-10 border border-black/50"
                                />
                            ))}
                        </tr>
                    ))}
                </tbody>
            </table>
        </div>
    )
}

function Blank({ label }: { label: string }) {
    return (
        <span className="inline-flex items-end gap-2">
            {label}:
            <span className="inline-block w-36 border-b border-black" />
        </span>
    )
}

function chunk<T>(items: readonly T[], size: number): T[][] {
    const groups: T[][] = []
    for (let index = 0; index < items.length; index += size) {
        groups.push(items.slice(index, index + size))
    }
    return groups
}

function PrintSheets({ preview }: { preview: boolean }) {
    const expenseList = SCENARIO_0_EXPENSE_LIST
    const statement = SCENARIO_1_STATEMENT
    return (
        <>
            <Sheet
                preview={preview}
                label={`${P.scenario(0)} · ${P.expenseList}`}
            >
                <h1 className="text-3xl font-semibold">{expenseList.title}</h1>
                {expenseList.kind === 'list' ? (
                    <ol className="flex list-decimal flex-col gap-3 pl-7 text-xl leading-snug">
                        {expenseList.items.map((item) => (
                            <li key={item}>{item}</li>
                        ))}
                    </ol>
                ) : null}
            </Sheet>

            <Sheet
                preview={preview}
                label={`${P.scenario(1)} · ${P.statement}`}
            >
                {statement.kind === 'table' ? (
                    <>
                        <h1 className="text-2xl font-semibold">
                            {statement.title}
                        </h1>
                        {statement.notes?.map((note) => (
                            <p key={note} className="text-sm">
                                {note}
                            </p>
                        ))}
                        <MaterialTable material={statement} />
                        {statement.footer ? (
                            <p className="text-sm font-semibold">
                                {statement.footer}
                            </p>
                        ) : null}
                    </>
                ) : null}
            </Sheet>

            <Sheet preview={preview} label={`${P.scenario(1)} · ${P.tickets}`}>
                <div className="grid gap-6 sm:grid-cols-2 print:grid-cols-2">
                    {SCENARIO_1_TICKETS.map((ticket) =>
                        ticket.kind === 'table' ? (
                            <div
                                key={ticket.title}
                                className="flex flex-col gap-2 border-2 border-dashed border-black/40 p-4 font-mono break-inside-avoid"
                            >
                                <span className="text-sm font-semibold">
                                    {ticket.title}
                                </span>
                                {ticket.notes?.map((note) => (
                                    <span key={note} className="text-xs">
                                        {note}
                                    </span>
                                ))}
                                <MaterialTable material={ticket} dense />
                            </div>
                        ) : null,
                    )}
                </div>
            </Sheet>

            {chunk(SCENARIO_2_QUESTIONS, CARDS_PER_PAGE).map((group) => (
                <Sheet
                    key={group[0].number}
                    preview={preview}
                    label={`${P.scenario(2)} · ${P.cards}`}
                >
                    <div className="grid gap-0 sm:grid-cols-2 print:grid-cols-2">
                        {group.map((question) => (
                            <div
                                key={question.number}
                                className="flex min-h-48 flex-col justify-center gap-4 border-2 border-dashed border-black/40 p-6 print:h-[124mm]"
                            >
                                <span className="text-sm tracking-wide text-black/60 uppercase">
                                    {P.card(question.number)}
                                </span>
                                <p className="text-2xl leading-snug font-medium">
                                    {question.question}
                                </p>
                            </div>
                        ))}
                    </div>
                </Sheet>
            ))}

            <Sheet preview={preview} label={P.susTitle}>
                <h1 className="text-2xl font-semibold">{P.susTitle}</h1>
                <div className="flex flex-wrap gap-x-8 gap-y-3 text-sm">
                    <Blank label={P.participant} />
                    <Blank label={P.date} />
                </div>
                <p className="text-sm">{SUS_INSTRUCTIONS}</p>
                <div className="overflow-x-auto">
                    <table className="w-full min-w-[32rem] border-collapse text-sm">
                        <thead>
                            <tr className="border-y-2 border-black">
                                <th className="w-8 px-2 py-2 text-left">#</th>
                                <th className="px-2 py-2 text-left">
                                    {P.susStatement}
                                </th>
                                {[1, 2, 3, 4, 5].map((value) => (
                                    <th
                                        key={value}
                                        className="w-10 px-1 py-2 text-center"
                                    >
                                        {value}
                                    </th>
                                ))}
                            </tr>
                        </thead>
                        <tbody>
                            {SUS_STATEMENTS.map((statement, index) => (
                                <tr
                                    key={statement}
                                    className="border-b border-black/20"
                                >
                                    <td className="px-2 py-3 align-top">
                                        {index + 1}
                                    </td>
                                    <td className="px-2 py-3">{statement}</td>
                                    {[1, 2, 3, 4, 5].map((value) => (
                                        <td
                                            key={value}
                                            className="px-1 py-3 text-center"
                                        >
                                            <span className="inline-block size-5 border border-black" />
                                        </td>
                                    ))}
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            </Sheet>

            <ObservationSheet preview={preview} />
        </>
    )
}

function ObservationSheet({ preview }: { preview: boolean }) {
    const scenarios = [
        { scenario: 0, block: rowsOf('escenario-0') },
        { scenario: 1, block: rowsOf('escenario-1') },
        { scenario: 2, block: rowsOf('escenario-2') },
    ]
    return (
        <Sheet preview={preview} label={P.sheetTitle}>
            <div className="flex flex-col gap-1">
                <h1 className="text-2xl font-semibold">{P.sheetTitle}</h1>
                <p className="text-sm text-black/70">{P.sheetHint}</p>
            </div>
            <table className="w-full table-fixed border-collapse text-xs break-inside-avoid">
                <thead>
                    <tr>
                        <th className="w-2/5 border border-black/50 bg-black/5 px-1.5 py-1 text-left font-semibold">
                            {P.data}
                        </th>
                        <th className="border border-black/50 bg-black/5 px-1.5 py-1 text-left font-semibold">
                            {P.value}
                        </th>
                    </tr>
                </thead>
                <tbody>
                    {OBSERVATION_SHEET_DATA.map(([label, options]) => (
                        <tr key={label}>
                            <td className="h-8 border border-black/50 px-1.5">
                                {label}
                            </td>
                            <td className="h-8 border border-black/50 px-1.5 text-black/60">
                                {options}
                            </td>
                        </tr>
                    ))}
                </tbody>
            </table>

            {scenarios.map(({ scenario, block }) =>
                block ? (
                    <section
                        key={scenario}
                        className="flex flex-col gap-1.5 break-inside-avoid"
                    >
                        <div className="flex flex-wrap items-end gap-x-6 gap-y-2 text-sm">
                            <span className="font-semibold">
                                {P.scenario(scenario)}
                            </span>
                            <Blank label={P.start} />
                            <Blank label={P.end} />
                        </div>
                        <BlankTable
                            columns={[
                                block.rowHeader,
                                ...(block.rows[0]?.fields.map(
                                    (field) => field.label,
                                ) ?? []),
                            ]}
                            rows={block.rows.map((row) => row.title)}
                            firstColumnClass="w-1/5"
                        />
                        {block.legend ? (
                            <p className="text-[11px] text-black/70">
                                {block.legend}
                            </p>
                        ) : null}
                    </section>
                ) : null,
            )}

            <section className="flex flex-col gap-1.5 break-inside-avoid">
                <span className="text-sm font-semibold">
                    {P.assistantTitle}
                </span>
                <BlankTable
                    columns={[P.question, P.answer]}
                    rows={assistantQuestions()}
                    firstColumnClass="w-2/5"
                />
            </section>

            <section className="flex flex-col gap-1.5 break-inside-avoid">
                <span className="text-sm font-semibold">{P.closingTitle}</span>
                <BlankTable
                    columns={[P.data, P.value]}
                    rows={OBSERVATION_SHEET_CLOSING}
                    firstColumnClass="w-2/5"
                />
            </section>
        </Sheet>
    )
}
