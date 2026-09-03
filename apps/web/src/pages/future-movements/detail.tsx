import { api } from '@wallet-bot/backend/api'
import { type RecurrenceFrequency, recurrenceHorizon } from '@wallet-bot/shared'
import { Button, IconButton, Select, SelectOption, TextField } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { type ReactNode, useId, useState } from 'react'
import { toast } from 'sonner'
import { AppBar } from '@/components/m3/app-bar'
import { DateField } from '@/components/m3/date-field'
import { DialogAction, M3Dialog } from '@/components/m3/dialog'
import { Icon } from '@/components/m3/icon'
import { useToastMutation } from '@/hooks/use-toast-mutation'
import { useFormatLocale, useT } from '@/lib/i18n'
import { formatMoney } from '@/lib/money'
import { cn } from '@/lib/utils'
import {
    type ActivityTransaction,
    centsToInput,
    dateInputValue,
    formatNumericDate,
    formatTransactionTime,
    frequencyLabel,
    frequencyOptionLabel,
    inputToCents,
    localDateTimeEpoch,
    normalizeAmount,
    seriesReachLabel,
    signedAmountCents,
    timeInputValue,
} from '../activity/helpers'

const FREQUENCIES: RecurrenceFrequency[] = [
    'daily',
    'weekly',
    'monthly',
    'yearly',
    'customDays',
]

/** Which occurrences an edit or a delete applies to. */
type RecurrenceScope = 'only-this' | 'all-future'

/**
 * One upcoming movement, presented the way `TransactionDetail` presents a past
 * one: the layout's occupant, headed by its own `AppBar`. `ListDetailLayout`
 * decides whether that lands in a sheet, a dialog or the split pane.
 *
 * Editing and deleting both ask the question a series forces: this occurrence,
 * or this one and the ones after it. Nothing is written until that is answered
 * — the scope is not a default the user can miss.
 */
export function FutureMovementDetail({
    movement,
    onClose,
}: {
    movement: ActivityTransaction
    onClose: () => void
}) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const formId = useId()

    const accounts = useQuery(api.v1.accounts.queries.list, {
        includeArchived: true,
    })
    const categories = useQuery(api.v1.categories.queries.listActive)
    const series = useQuery(api.v1.recurrences.queries.get, {
        recurrenceId: movement.recurrenceId,
    })

    const updateOne = useMutation(api.v1.transactions.mutations.update)
    const archiveOne = useMutation(api.v1.transactions.mutations.archive)
    const updateFuture = useMutation(api.v1.recurrences.mutations.updateFuture)
    const deleteFuture = useMutation(api.v1.recurrences.mutations.deleteFuture)
    const splitSeries = useMutation(api.v1.recurrences.mutations.splitSeries)
    const addOccurrences = useMutation(
        api.v1.recurrences.mutations.addOccurrences,
    )
    const { pending, run } = useToastMutation()

    const [editing, setEditing] = useState(false)
    const [name, setName] = useState(movement.name)
    const [description, setDescription] = useState(movement.description ?? '')
    const [amount, setAmount] = useState(centsToInput(movement.amount))
    const [date, setDate] = useState(dateInputValue(movement.date))
    const [time, setTime] = useState(timeInputValue(movement.date))
    const [accountId, setAccountId] = useState(movement.accountId)
    const [categoryId, setCategoryId] = useState(movement.categoryId)
    // Null until the user picks one, and resolved against the rule at read
    // time. Seeding them from `series` at mount looked equivalent but was not:
    // the query is still loading on the first render, so the fallback became
    // the "current" cadence and every save looked like a cadence change.
    const [frequencyChoice, setFrequencyChoice] =
        useState<RecurrenceFrequency | null>(null)
    const [dayIntervalChoice, setDayIntervalChoice] = useState<number | null>(
        null,
    )
    const frequency: RecurrenceFrequency =
        frequencyChoice ?? series?.frequency ?? 'monthly'
    const dayInterval =
        dayIntervalChoice ??
        (series?.dayInterval === undefined ? 15 : Number(series.dayInterval))

    // Which question is on screen, if any. Nothing is written until it is
    // answered, so this doubles as "an operation is staged".
    const [asking, setAsking] = useState<'save' | 'delete' | null>(null)

    const account = accounts?.find((a) => a.id === movement.accountId)
    const category = categories?.find((c) => c.id === movement.categoryId)

    const cents = signedAmountCents(movement)
    const sign = cents < 0 ? '-' : cents > 0 ? '+' : ''

    // Only an open-ended series can be topped up. One with an end date is
    // already complete, and running past a boundary the user set on purpose
    // would be editing the rule rather than extending it.
    const topUp =
        series && series.endDate === undefined
            ? recurrenceHorizon(
                  series.frequency,
                  series.dayInterval === undefined
                      ? undefined
                      : Number(series.dayInterval),
              ).count
            : null

    const seriesReach = series
        ? seriesReachLabel(series, movement.recurrenceIndex, t, (value) =>
              formatNumericDate(value, formatLocale),
          )
        : null

    const editedDate = localDateTimeEpoch(date, time)
    // A cadence change cannot be confined to one occurrence: every later date
    // is projected from the anchor, so "from here on, weekly" is two rules.
    const cadenceChanged = series
        ? frequency !== series.frequency ||
          (frequency === 'customDays' &&
              dayInterval !==
                  (series.dayInterval === undefined
                      ? 0
                      : Number(series.dayInterval)))
        : false
    const anchorChanged = editedDate !== movement.date

    function validate(): { name: string; amount: bigint } | null {
        const trimmed = name.trim()
        if (!trimmed) {
            toast.error(t.futureMovements.titleRequired)
            return null
        }
        const cents = inputToCents(amount)
        if (cents === null || cents <= 0n) {
            toast.error(t.futureMovements.amountGreaterThanZero)
            return null
        }
        return { name: trimmed, amount: cents }
    }

    function apply(scope: RecurrenceScope) {
        setAsking(null)
        if (asking === 'delete') {
            const promise =
                scope === 'only-this'
                    ? archiveOne({ id: movement.id })
                    : deleteFuture({ transactionId: movement.id })
            void run(
                promise,
                {
                    loading: t.common.saving,
                    success:
                        scope === 'only-this'
                            ? t.futureMovements.deletedOnlyThis
                            : t.futureMovements.deletedAllFuture,
                    error: t.common.saveFailed,
                },
                onClose,
            )
            return
        }

        const valid = validate()
        if (!valid) return
        const patch = {
            name: valid.name,
            description: description.trim() ? description.trim() : null,
            amount: valid.amount,
            accountId,
            categoryId,
        }

        // Re-cadencing or re-anchoring the tail is a split, not an update:
        // the occurrences before this one keep their own spacing.
        const promise =
            scope === 'all-future' && (cadenceChanged || anchorChanged)
                ? splitSeries({
                      transactionId: movement.id,
                      recurrenceId: crypto.randomUUID(),
                      frequency,
                      dayInterval:
                          frequency === 'customDays'
                              ? BigInt(dayInterval)
                              : undefined,
                      date: editedDate,
                      dateConfirmed: true,
                      timeStatus: 'confirmed',
                      patch,
                  })
                : scope === 'all-future'
                  ? updateFuture({ transactionId: movement.id, patch })
                  : updateOne({
                        id: movement.id,
                        name: patch.name,
                        description: patch.description ?? undefined,
                        amount: patch.amount,
                        accountId: patch.accountId,
                        categoryId: patch.categoryId,
                        date: editedDate,
                        dateConfirmed: true,
                        timeStatus: 'confirmed',
                    })

        void run(
            promise,
            {
                loading: t.common.saving,
                success:
                    scope === 'only-this'
                        ? t.futureMovements.savedOnlyThis
                        : t.futureMovements.savedAllFuture,
                error: t.common.saveFailed,
            },
            () => {
                setEditing(false)
                // A split replaces this occurrence with the new series' anchor,
                // so the row behind this detail is gone.
                if (scope === 'all-future' && (cadenceChanged || anchorChanged))
                    onClose()
            },
        )
    }

    return (
        <>
            <AppBar
                title={
                    editing
                        ? t.futureMovements.editMovement
                        : t.futureMovements.detail
                }
                leading={
                    <IconButton
                        aria-label={t.common.close}
                        onPress={onClose}
                        className="text-on-surface-variant"
                    >
                        <Icon name="close" />
                    </IconButton>
                }
                actions={
                    <>
                        {editing ? null : (
                            <IconButton
                                aria-label={t.futureMovements.edit}
                                onPress={() => setEditing(true)}
                                className="text-on-surface-variant"
                            >
                                <Icon name="edit" />
                            </IconButton>
                        )}
                        <IconButton
                            aria-label={t.futureMovements.delete}
                            onPress={() => setAsking('delete')}
                            isDisabled={pending}
                            className="text-on-surface-variant"
                        >
                            <Icon name="delete" />
                        </IconButton>
                    </>
                }
            />

            <form
                id={formId}
                className="flex flex-1 flex-col px-4 pb-8"
                onSubmit={(event) => {
                    event.preventDefault()
                    if (validate()) setAsking('save')
                }}
            >
                <div className="flex flex-col items-center pt-2 pb-4">
                    {editing ? (
                        <TextField
                            aria-label={t.futureMovements.titlePlaceholder}
                            variant="outlined"
                            className="w-full"
                            value={name}
                            onChange={setName}
                            placeholder={t.futureMovements.titlePlaceholder}
                        />
                    ) : (
                        <>
                            <h2 className="text-xl font-bold">
                                {movement.name}
                            </h2>
                            <span
                                className={cn(
                                    'mt-3 text-2xl font-bold',
                                    cents > 0
                                        ? 'text-positive'
                                        : 'text-on-surface',
                                )}
                            >
                                {sign
                                    ? `${sign} ${formatMoney(Math.abs(cents), movement.currency, formatLocale)}`
                                    : formatMoney(
                                          cents,
                                          movement.currency,
                                          formatLocale,
                                      )}
                            </span>
                        </>
                    )}
                </div>

                <div className="divide-y divide-outline-variant">
                    {editing ? (
                        <FieldRow
                            icon={<Icon name="payments" />}
                            label={t.futureMovements.amount}
                        >
                            <TextField
                                aria-label={t.futureMovements.amount}
                                variant="outlined"
                                inputMode="decimal"
                                value={amount}
                                onChange={(next) =>
                                    setAmount(normalizeAmount(next))
                                }
                            />
                        </FieldRow>
                    ) : null}

                    {series ? (
                        <FieldRow
                            icon={<Icon name="repeat" />}
                            label={t.futureMovements.frequency}
                        >
                            {editing ? (
                                <div className="flex flex-col gap-2">
                                    <Select
                                        aria-label={t.futureMovements.frequency}
                                        variant="outlined"
                                        selectedKey={frequency}
                                        onSelectionChange={(key) =>
                                            setFrequencyChoice(
                                                String(
                                                    key,
                                                ) as RecurrenceFrequency,
                                            )
                                        }
                                    >
                                        {FREQUENCIES.map((value) => (
                                            <SelectOption key={value}>
                                                {frequencyOptionLabel(value, t)}
                                            </SelectOption>
                                        ))}
                                    </Select>
                                    {frequency === 'customDays' ? (
                                        <div className="flex items-center gap-2">
                                            <span className="m3-body-medium shrink-0">
                                                {
                                                    t.addManual
                                                        .recurrenceRepeatEvery
                                                }
                                            </span>
                                            <TextField
                                                aria-label={
                                                    t.addManual
                                                        .recurrenceRepeatEvery
                                                }
                                                variant="outlined"
                                                inputMode="numeric"
                                                className="w-20"
                                                value={dayInterval.toString()}
                                                onChange={(next: string) => {
                                                    const parsed =
                                                        Number.parseInt(
                                                            next,
                                                            10,
                                                        )
                                                    if (
                                                        !Number.isFinite(
                                                            parsed,
                                                        ) ||
                                                        parsed < 1
                                                    )
                                                        return
                                                    setDayIntervalChoice(parsed)
                                                }}
                                            />
                                            <span className="m3-body-medium shrink-0">
                                                {t.addManual.recurrenceDaysUnit}
                                            </span>
                                        </div>
                                    ) : null}
                                </div>
                            ) : (
                                <span className="flex items-center justify-end gap-2">
                                    <span>
                                        {frequencyLabel(
                                            series.frequency,
                                            series.dayInterval === undefined
                                                ? 1
                                                : Number(series.dayInterval),
                                            t,
                                        )}
                                    </span>
                                    {seriesReach ? (
                                        <span className="font-normal text-on-surface-variant">
                                            {seriesReach}
                                        </span>
                                    ) : null}
                                </span>
                            )}
                        </FieldRow>
                    ) : null}

                    <FieldRow
                        icon={<Icon name="calendar_month" />}
                        label={t.futureMovements.date}
                    >
                        {editing ? (
                            <DateField
                                value={date}
                                onChange={setDate}
                                label={t.futureMovements.date}
                                compact
                                className="w-auto"
                            />
                        ) : (
                            formatNumericDate(
                                new Date(Number(movement.date)),
                                formatLocale,
                            )
                        )}
                    </FieldRow>

                    <FieldRow
                        icon={<Icon name="schedule" />}
                        label={t.transaction.time}
                    >
                        {editing ? (
                            <input
                                type="time"
                                aria-label={t.transaction.time}
                                value={time}
                                onChange={(event) =>
                                    setTime(event.target.value)
                                }
                                className="rounded-lg border border-outline bg-transparent px-3 py-2 text-on-surface"
                            />
                        ) : (
                            formatTransactionTime(movement.date, formatLocale)
                        )}
                    </FieldRow>

                    <FieldRow
                        icon={<Icon name="account_balance" />}
                        label={t.futureMovements.account}
                    >
                        {editing ? (
                            <Select
                                aria-label={t.futureMovements.account}
                                variant="outlined"
                                selectedKey={accountId}
                                onSelectionChange={(key) =>
                                    setAccountId(String(key))
                                }
                            >
                                {(accounts ?? [])
                                    .filter(
                                        (a) =>
                                            !a.isArchived ||
                                            a.id === movement.accountId,
                                    )
                                    .map((a) => (
                                        <SelectOption key={a.id}>
                                            {`${a.name} · ${a.currency}`}
                                        </SelectOption>
                                    ))}
                            </Select>
                        ) : (
                            (account?.name ?? '—')
                        )}
                    </FieldRow>

                    <FieldRow
                        icon={<Icon name="sell" />}
                        label={t.futureMovements.category}
                    >
                        {editing ? (
                            <Select
                                aria-label={t.futureMovements.category}
                                variant="outlined"
                                selectedKey={categoryId}
                                onSelectionChange={(key) =>
                                    setCategoryId(String(key))
                                }
                            >
                                {(categories ?? []).map((c) => (
                                    <SelectOption key={c.id}>
                                        {c.name}
                                    </SelectOption>
                                ))}
                            </Select>
                        ) : (
                            (category?.name ?? '—')
                        )}
                    </FieldRow>

                    <FieldRow
                        icon={<Icon name="notes" />}
                        label={t.futureMovements.description}
                        stacked
                    >
                        {editing ? (
                            <TextField
                                aria-label={t.futureMovements.description}
                                variant="outlined"
                                className="w-full"
                                value={description}
                                onChange={setDescription}
                                placeholder={
                                    t.futureMovements.descriptionPlaceholder
                                }
                            />
                        ) : (
                            <span
                                className={
                                    movement.description
                                        ? undefined
                                        : 'text-on-surface-variant'
                                }
                            >
                                {movement.description ||
                                    t.futureMovements.noDescription}
                            </span>
                        )}
                    </FieldRow>
                </div>

                {editing ? (
                    <div className="flex flex-col items-stretch gap-2 pt-6">
                        <Button
                            type="submit"
                            variant="filled"
                            isDisabled={pending}
                        >
                            {t.futureMovements.saveChanges}
                        </Button>
                        <Button
                            type="button"
                            variant="text"
                            isDisabled={pending}
                            onPress={() => setEditing(false)}
                        >
                            {t.futureMovements.cancel}
                        </Button>
                    </div>
                ) : topUp !== null && series ? (
                    <div className="flex flex-col items-stretch gap-2 pt-6">
                        <Button
                            type="button"
                            variant="filled"
                            isDisabled={pending}
                            onPress={() =>
                                void run(
                                    addOccurrences({
                                        recurrenceId: series.id,
                                    }),
                                    {
                                        loading: t.futureMovements.addingMore,
                                        success: t.futureMovements.addedMore({
                                            count: topUp,
                                        }),
                                        error: t.futureMovements.addMoreFailed,
                                    },
                                )
                            }
                        >
                            {t.futureMovements.addMore({ count: topUp })}
                        </Button>
                        <p className="m3-body-small text-center text-on-surface-variant">
                            {t.futureMovements.addMoreHint}
                        </p>
                    </div>
                ) : null}
            </form>

            <M3Dialog
                open={asking !== null}
                onOpenChange={(next) => {
                    if (!next) setAsking(null)
                }}
                title={
                    asking === 'delete'
                        ? t.futureMovements.deleteRecurring
                        : t.futureMovements.editMovement
                }
                description={
                    asking === 'delete'
                        ? t.futureMovements.scopeDeleteDescription(
                              movement.name,
                          )
                        : t.futureMovements.scopeEditDescription
                }
                actions={
                    <>
                        <DialogAction
                            label={t.futureMovements.cancel}
                            onPress={() => setAsking(null)}
                        />
                        <DialogAction
                            label={t.futureMovements.scopeOnlyThis}
                            isDisabled={asking === 'save' && cadenceChanged}
                            destructive={asking === 'delete'}
                            onPress={() => apply('only-this')}
                        />
                        <DialogAction
                            label={t.futureMovements.scopeAllFuture}
                            destructive={asking === 'delete'}
                            onPress={() => apply('all-future')}
                        />
                    </>
                }
            >
                {asking === 'save' && cadenceChanged ? (
                    <p className="m3-body-small pt-3 text-on-surface-variant">
                        {t.futureMovements.scopeOnlyThisUnavailable}
                    </p>
                ) : null}
            </M3Dialog>
        </>
    )
}

/**
 * A labelled row of the receipt, matching `ReceiptRow` in the Activity detail:
 * the label and its glyph on one side, the value on the other.
 */
function FieldRow({
    icon,
    label,
    stacked = false,
    children,
}: {
    icon: ReactNode
    label: string
    stacked?: boolean
    children: ReactNode
}) {
    const heading = (
        <div className="flex items-center gap-2 text-sm font-medium text-on-surface-variant [&_svg]:size-4">
            {icon}
            <span>{label}</span>
        </div>
    )

    return stacked ? (
        <div className="space-y-2 py-4">
            {heading}
            <div className="font-medium">{children}</div>
        </div>
    ) : (
        <div className="flex items-center justify-between gap-4 py-4">
            {heading}
            <div className="text-right font-medium">{children}</div>
        </div>
    )
}
