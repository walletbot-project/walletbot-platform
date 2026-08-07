import { CalendarClock, Info } from 'lucide-react'
import { useMemo, useState } from 'react'
import { toast } from 'sonner'
import {
    estimatedDescription,
    formatTransactionTime,
    transactionTimeStatus,
} from '../activity/helpers'
import { TransactionRow } from '../activity/transaction-row'
import { FutureMovementDetailsSheet } from './details-sheet'
import {
    buildFutureEntries,
    buildMockMovements,
    FREQUENCY_LABELS,
    type FutureMovement,
    identitiesFor,
    type RecurrenceScope,
    stepDate,
} from './helpers'

export function FutureMovements() {
    const [now] = useState(() => Date.now())
    const [movements, setMovements] = useState<FutureMovement[]>(() =>
        buildMockMovements(now),
    )
    const [selectedId, setSelectedId] = useState<string | null>(null)

    const entries = useMemo(
        () => buildFutureEntries(movements, now),
        [movements, now],
    )
    const selected = movements.find((m) => m.id === selectedId) ?? null

    function handleSave(
        id: string,
        patch: Partial<FutureMovement>,
        scope: RecurrenceScope,
    ) {
        const target = movements.find((m) => m.id === id)
        if (!target) return

        // "This and future": the edited occurrence becomes the new anchor and
        // the later occurrences of the rule are re-projected from it — so moving
        // a monthly movement to the 18th shifts the rest to the 18th, and moving
        // a weekly/custom one recalculates the following ones from the new date.
        const laterSorted =
            scope === 'all-future'
                ? movements
                      .filter(
                          (m) =>
                              m.ruleId === target.ruleId &&
                              m.date > target.date,
                      )
                      .sort((a, b) => Number(a.date - b.date))
                : []
        const stepById = new Map(laterSorted.map((m, i) => [m.id, i + 1]))
        const anchor = patch.date ?? target.date
        const frequency = patch.frequency ?? target.frequency
        const dayInterval = patch.dayInterval ?? target.dayInterval

        setMovements((current) =>
            current.map((m) => {
                if (m.id === id) return { ...m, ...patch }
                const step = stepById.get(m.id)
                if (step !== undefined) {
                    const rest: Partial<FutureMovement> = { ...patch }
                    delete rest.date
                    return {
                        ...m,
                        ...rest,
                        date: stepDate(anchor, frequency, dayInterval, step),
                    }
                }
                return m
            }),
        )
        toast.success(
            scope === 'only-this'
                ? 'Cambios aplicados a este movimiento'
                : 'Cambios aplicados a este y los futuros',
        )
    }

    function handleDelete(id: string, scope: RecurrenceScope) {
        const target = movements.find((m) => m.id === id)
        if (!target) return
        setMovements((current) =>
            current.filter((m) => {
                if (m.id === id) return false
                if (
                    scope === 'all-future' &&
                    m.ruleId === target.ruleId &&
                    m.date > target.date
                ) {
                    return false
                }
                return true
            }),
        )
        setSelectedId(null)
        toast.success(
            scope === 'only-this'
                ? 'Movimiento eliminado'
                : 'Movimiento y sus futuros eliminados',
        )
    }

    return (
        <div className="flex flex-1 flex-col">
            <div className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-4 p-4">
                <div className="flex items-start gap-3 rounded-xl border border-[#21C4B6]/40 bg-[#21C4B6]/10 px-4 py-3">
                    <Info className="mt-0.5 size-4 shrink-0 text-[#11796F]" />
                    <p className="text-sm text-[#11796F]">
                        Estos son tus movimientos recurrentes que todavía no
                        ocurrieron. No aparecen en Actividad hasta que suceden.
                    </p>
                </div>

                {entries.length === 0 ? (
                    <div className="flex flex-1 flex-col items-center justify-center gap-3 py-12 text-center">
                        <div className="flex size-12 items-center justify-center rounded-full bg-muted">
                            <CalendarClock className="size-5 text-muted-foreground" />
                        </div>
                        <p className="text-sm text-muted-foreground">
                            No tenés movimientos futuros programados
                        </p>
                    </div>
                ) : (
                    <div className="flex flex-col gap-2">
                        {entries.map((entry) =>
                            entry.kind === 'header' ? (
                                <h2
                                    key={entry.key}
                                    className="px-1 pt-3 text-sm font-bold text-foreground first:pt-0"
                                >
                                    {entry.label}
                                </h2>
                            ) : (
                                <TransactionRow
                                    key={entry.key}
                                    title={entry.txn.name}
                                    amountCents={entry.amountCents}
                                    currency={entry.txn.currency}
                                    dateConfirmed={entry.txn.dateConfirmed}
                                    timeLabel={formatTransactionTime(
                                        entry.txn.date,
                                    )}
                                    timeStatus={transactionTimeStatus(
                                        entry.txn,
                                    )}
                                    description={[
                                        FREQUENCY_LABELS[entry.txn.frequency],
                                        estimatedDescription(entry.txn),
                                    ]
                                        .filter(Boolean)
                                        .join(' · ')}
                                    identities={identitiesFor(entry.txn)}
                                    onClick={() => setSelectedId(entry.txn.id)}
                                />
                            ),
                        )}
                    </div>
                )}
            </div>

            <FutureMovementDetailsSheet
                movement={selected}
                open={selectedId !== null}
                onOpenChange={(open) => {
                    if (!open) setSelectedId(null)
                }}
                onSave={handleSave}
                onDelete={handleDelete}
            />
        </div>
    )
}
