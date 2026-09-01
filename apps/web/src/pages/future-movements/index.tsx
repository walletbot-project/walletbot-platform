import { IconButton } from 'actify'
import { useCallback, useMemo, useState } from 'react'
import { useNavigate, useOutletContext, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
import { ListDetailLayout } from '@/components/m3/list-detail-layout'
import { StateMessage } from '@/components/m3/state-message'
import { useFormatLocale, useT } from '@/lib/i18n'
import {
    estimatedDescription,
    formatTransactionTime,
    transactionTimeStatus,
} from '../activity/helpers'
import { TransactionRow } from '../activity/transaction-row'
import { FutureMovementDetail } from './detail'
import {
    buildFutureEntries,
    buildMockMovements,
    type FutureMovement,
    frequencyLabel,
    identitiesFor,
    type RecurrenceScope,
    stepDate,
} from './helpers'

/**
 * The upcoming side of Activity: the movements a recurrence rule will produce
 * that have not happened yet.
 *
 * Structurally this is the Activity list — the same `ListDetailLayout`, the
 * same `TransactionRow`, the same day headers — so what is open is the URL's
 * business and a detail behaves the same at every width. The differences are
 * deliberate: the list runs ascending (the soonest movement belongs at the
 * top, not the newest), and there is no filter bar, because a rule's
 * projection is not a query over history.
 *
 * Backed by mock data — nothing here is persisted yet (see
 * docs/recurrency-design.md).
 */
export function FutureMovements() {
    const t = useT()
    const locale = useFormatLocale()
    const navigate = useNavigate()
    const [now] = useState(() => Date.now())
    const [movements, setMovements] = useState<FutureMovement[]>(() =>
        buildMockMovements(now),
    )

    const entries = useMemo(
        () => buildFutureEntries(movements, now, t, locale),
        [movements, now, t, locale],
    )

    const handleSave = useCallback(
        (
            id: string,
            patch: Partial<FutureMovement>,
            scope: RecurrenceScope,
        ) => {
            setMovements((current) => {
                const target = current.find((m) => m.id === id)
                if (!target) return current

                // "This and future": the edited occurrence becomes the new
                // anchor and the later occurrences of the rule are re-projected
                // from it — so moving a monthly movement to the 18th shifts the
                // rest to the 18th, and moving a weekly/custom one recalculates
                // the following ones from the new date.
                const laterSorted =
                    scope === 'all-future'
                        ? current
                              .filter(
                                  (m) =>
                                      m.ruleId === target.ruleId &&
                                      m.date > target.date,
                              )
                              .sort((a, b) => Number(a.date - b.date))
                        : []
                const stepById = new Map(
                    laterSorted.map((m, i) => [m.id, i + 1]),
                )
                const anchor = patch.date ?? target.date
                const frequency = patch.frequency ?? target.frequency
                const dayInterval = patch.dayInterval ?? target.dayInterval

                return current.map((m) => {
                    if (m.id === id) return { ...m, ...patch }
                    const step = stepById.get(m.id)
                    if (step !== undefined) {
                        const rest: Partial<FutureMovement> = { ...patch }
                        delete rest.date
                        return {
                            ...m,
                            ...rest,
                            date: stepDate(
                                anchor,
                                frequency,
                                dayInterval,
                                step,
                            ),
                        }
                    }
                    return m
                })
            })
            toast.success(
                scope === 'only-this'
                    ? t.futureMovements.savedOnlyThis
                    : t.futureMovements.savedAllFuture,
            )
        },
        [t],
    )

    const handleDelete = useCallback(
        (id: string, scope: RecurrenceScope) => {
            setMovements((current) => {
                const target = current.find((m) => m.id === id)
                if (!target) return current
                return current.filter((m) => {
                    if (m.id === id) return false
                    if (
                        scope === 'all-future' &&
                        m.ruleId === target.ruleId &&
                        m.date > target.date
                    ) {
                        return false
                    }
                    return true
                })
            })
            toast.success(
                scope === 'only-this'
                    ? t.futureMovements.deletedOnlyThis
                    : t.futureMovements.deletedAllFuture,
            )
        },
        [t],
    )

    const list = (
        <>
            <AppBar
                title={t.futureMovements.title}
                leading={
                    <IconButton
                        aria-label={t.common.goBack}
                        onPress={() => navigate(-1)}
                        className="text-on-surface-variant"
                    >
                        <Icon name="arrow_back" />
                    </IconButton>
                }
            />
            <div className="min-h-0 flex-1 overflow-y-auto">
                <div className="flex flex-col gap-4 pt-2 pb-20">
                    <div className="mx-4 flex items-start gap-3 rounded-xl bg-secondary-container px-4 py-3 text-on-secondary-container">
                        <Icon
                            name="info"
                            size={20}
                            className="mt-0.5 shrink-0"
                        />
                        <p className="m3-body-medium">
                            {t.futureMovements.info}
                        </p>
                    </div>

                    {entries.length === 0 ? (
                        <p className="m3-body-large py-12 text-center text-on-surface-variant">
                            {t.futureMovements.empty}
                        </p>
                    ) : (
                        <div className="flex flex-col gap-2.5 px-4">
                            {entries.map((entry) =>
                                entry.kind === 'header' ? (
                                    <h2
                                        key={entry.key}
                                        className="pt-2 text-base font-bold first:pt-0"
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
                                            locale,
                                        )}
                                        timeStatus={transactionTimeStatus(
                                            entry.txn,
                                        )}
                                        description={[
                                            frequencyLabel(
                                                entry.txn.frequency,
                                                t,
                                            ),
                                            estimatedDescription(
                                                entry.txn,
                                                t,
                                                locale,
                                            ),
                                        ]
                                            .filter(Boolean)
                                            .join(' · ')}
                                        identities={identitiesFor(entry.txn, t)}
                                        onClick={() =>
                                            navigate(
                                                `/future-movements/${entry.txn.id}`,
                                            )
                                        }
                                    />
                                ),
                            )}
                        </div>
                    )}
                </div>
            </div>
        </>
    )

    const outletContext: FutureMovementsOutletContext = useMemo(
        () => ({ movements, onSave: handleSave, onDelete: handleDelete }),
        [movements, handleSave, handleDelete],
    )

    return (
        <ListDetailLayout
            list={list}
            closeTo="/future-movements"
            detailTitle={t.futureMovements.detail}
            context={outletContext}
            placeholder={
                <div className="flex flex-1 items-center justify-center p-8">
                    <p className="m3-body-large max-w-xs text-center text-on-surface-variant">
                        {t.futureMovements.selectDetail}
                    </p>
                </div>
            }
        />
    )
}

/**
 * What the list offers its child route. The movements are mock state owned by
 * the list, so unlike Activity — where the detail re-queries by id — the
 * detail is handed the collection and the two mutators.
 */
export type FutureMovementsOutletContext = {
    movements: readonly FutureMovement[]
    onSave: (
        id: string,
        patch: Partial<FutureMovement>,
        scope: RecurrenceScope,
    ) => void
    onDelete: (id: string, scope: RecurrenceScope) => void
}

/** `/future-movements/:movementId` — one upcoming movement's detail. */
export function FutureMovementDetailRoute() {
    const t = useT()
    const navigate = useNavigate()
    const { movementId } = useParams()
    const { movements, onSave, onDelete } =
        useOutletContext<FutureMovementsOutletContext>()

    const movement = movements.find((m) => m.id === movementId) ?? null

    if (!movement) {
        return (
            <StateMessage
                icon="search_off"
                tone="error"
                title={t.common.notFoundTitle}
                detail={t.common.notFoundDescription}
            />
        )
    }

    return (
        <FutureMovementDetail
            movement={movement}
            onClose={() => navigate('/future-movements')}
            onSave={onSave}
            onDelete={onDelete}
        />
    )
}
