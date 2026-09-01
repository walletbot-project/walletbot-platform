import { IconButton } from 'actify'
import { type ReactNode, useState } from 'react'
import { toast } from 'sonner'
import { AppBar } from '@/components/m3/app-bar'
import { DateField } from '@/components/m3/date-field'
import { DialogAction, M3Dialog } from '@/components/m3/dialog'
import { Icon } from '@/components/m3/icon'
import { OptionSheet } from '@/components/m3/option-sheet'
import { PickerField } from '@/components/m3/picker-field'
import { TimeField } from '@/components/m3/time-field'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { useFormatLocale, useT } from '@/lib/i18n'
import { formatMoney } from '@/lib/money'
import { cn } from '@/lib/utils'
import { formatNumericDate, formatTransactionTime } from '../activity/helpers'
import {
    FREQUENCY_OPTIONS,
    type FutureMovement,
    frequencyLabel,
    fromDateTimeInputs,
    MOCK_ACCOUNTS,
    MOCK_CATEGORIES,
    type MockFrequency,
    type RecurrenceScope,
    toDateInput,
    toTimeInput,
} from './helpers'

function signedCents(movement: FutureMovement): number {
    const amount = Number(movement.amount)
    return movement.type === 'expense' ? -Math.abs(amount) : Math.abs(amount)
}

/**
 * One upcoming movement, presented the way `TransactionDetail` presents a past
 * one: the layout's occupant, headed by its own `AppBar`, with a single action
 * that toggles between reading and editing. `ListDetailLayout` decides whether
 * that lands in a sheet, a dialog or the split pane.
 *
 * The one thing this detail has that the Activity one does not is the scope
 * prompt: editing or deleting an occurrence of a rule has to say whether it
 * means this one or this one and the ones after it.
 */
export function FutureMovementDetail({
    movement,
    onClose,
    onSave,
    onDelete,
}: {
    movement: FutureMovement
    onClose: () => void
    onSave: (
        id: string,
        patch: Partial<FutureMovement>,
        scope: RecurrenceScope,
    ) => void
    onDelete: (id: string, scope: RecurrenceScope) => void
}) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const [editing, setEditing] = useState(false)
    const [name, setName] = useState(movement.name)
    const [description, setDescription] = useState(movement.description ?? '')
    const [amount, setAmount] = useState(
        Math.round(Math.abs(Number(movement.amount)) / 100).toString(),
    )
    const [date, setDate] = useState(toDateInput(movement.date))
    const [time, setTime] = useState(toTimeInput(movement.date))
    const [accountId, setAccountId] = useState(movement.accountId)
    const [categoryId, setCategoryId] = useState(movement.categoryId)
    const [frequency, setFrequency] = useState<MockFrequency>(
        movement.frequency,
    )
    const [dayInterval, setDayInterval] = useState(movement.dayInterval ?? 15)

    // Which picker is open, if any — the same one-at-a-time modal discipline
    // the transaction form uses for its account and category sheets.
    const [openPicker, setOpenPicker] = useState<
        'account' | 'category' | 'frequency' | null
    >(null)
    // The scope prompt shown before committing an edit or a delete.
    const [pendingScope, setPendingScope] = useState<'save' | 'delete' | null>(
        null,
    )

    const cents = signedCents(movement)
    const sign = cents < 0 ? '-' : cents > 0 ? '+' : ''

    function buildPatch(): Partial<FutureMovement> | null {
        const trimmedName = name.trim()
        if (!trimmedName) {
            toast.error(t.futureMovements.titleRequired)
            return null
        }
        const parsedAmount = Number(amount.trim().replace(',', '.'))
        if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
            toast.error(t.futureMovements.amountGreaterThanZero)
            return null
        }
        return {
            name: trimmedName,
            description: description.trim() ? description.trim() : null,
            amount: BigInt(Math.round(parsedAmount * 100)),
            date: fromDateTimeInputs(date, time),
            accountId,
            categoryId,
            frequency,
            dayInterval:
                frequency === 'customDays'
                    ? Math.max(1, dayInterval)
                    : undefined,
        }
    }

    function handleSaveClick() {
        if (buildPatch() === null) return
        setPendingScope('save')
    }

    function applyScope(scope: RecurrenceScope) {
        if (pendingScope === 'delete') {
            onDelete(movement.id, scope)
            setPendingScope(null)
            onClose()
            return
        }
        const patch = buildPatch()
        if (!patch) {
            setPendingScope(null)
            return
        }
        onSave(movement.id, patch, scope)
        setPendingScope(null)
        setEditing(false)
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
                        <IconButton
                            aria-label={editing ? t.common.save : t.common.edit}
                            onPress={() =>
                                editing ? handleSaveClick() : setEditing(true)
                            }
                            className="text-on-surface-variant"
                        >
                            <Icon name={editing ? 'check' : 'edit'} />
                        </IconButton>
                        <IconButton
                            aria-label={t.common.delete}
                            onPress={() => setPendingScope('delete')}
                            className="text-on-surface-variant"
                        >
                            <Icon name="delete" />
                        </IconButton>
                    </>
                }
            />

            <form
                className="flex flex-1 flex-col px-4 pb-8"
                onSubmit={(event) => {
                    event.preventDefault()
                    handleSaveClick()
                }}
            >
                <div className="flex flex-col items-center pt-2 pb-4">
                    {editing ? (
                        <Input
                            value={name}
                            onChange={(event) => setName(event.target.value)}
                            className="h-10 max-w-sm text-center text-lg font-bold"
                            aria-label={t.futureMovements.titlePlaceholder}
                            required
                        />
                    ) : (
                        <h2 className="text-xl font-bold">{movement.name}</h2>
                    )}

                    {editing ? (
                        <Input
                            value={amount}
                            onChange={(event) => setAmount(event.target.value)}
                            inputMode="decimal"
                            className="mt-3 h-11 max-w-52 text-center text-2xl font-bold"
                            aria-label={t.futureMovements.amount}
                            required
                        />
                    ) : (
                        <span
                            className={cn(
                                'mt-3 text-2xl font-bold',
                                cents > 0 ? 'text-positive' : 'text-on-surface',
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
                    )}
                </div>

                <div className="divide-y divide-outline-variant">
                    <ReceiptRow
                        icon={<Icon name="event_repeat" />}
                        label={t.futureMovements.frequency}
                        stacked={editing}
                    >
                        {editing ? (
                            <div className="flex flex-col gap-2">
                                <PickerField
                                    label={t.futureMovements.frequency}
                                    value={frequencyLabel(frequency, t)}
                                    compact
                                    onClick={() => setOpenPicker('frequency')}
                                />
                                {frequency === 'customDays' ? (
                                    <div className="flex items-center gap-2">
                                        <span className="m3-body-medium text-on-surface-variant">
                                            {t.addManual.recurrenceRepeatEvery}
                                        </span>
                                        <Input
                                            inputMode="numeric"
                                            value={dayInterval.toString()}
                                            onChange={(event) => {
                                                const parsed = Number.parseInt(
                                                    event.target.value,
                                                    10,
                                                )
                                                if (
                                                    !Number.isFinite(parsed) ||
                                                    parsed < 1
                                                ) {
                                                    return
                                                }
                                                setDayInterval(parsed)
                                            }}
                                            className="h-10 w-20 text-center"
                                            aria-label={
                                                t.addManual
                                                    .recurrenceRepeatEvery
                                            }
                                        />
                                        <span className="m3-body-medium text-on-surface-variant">
                                            {t.addManual.recurrenceDaysUnit}
                                        </span>
                                    </div>
                                ) : null}
                            </div>
                        ) : (
                            <span>
                                {frequencyLabel(movement.frequency, t)}
                                {movement.frequency === 'customDays' &&
                                movement.dayInterval
                                    ? ` (${movement.dayInterval} ${t.addManual.recurrenceDaysUnit})`
                                    : ''}
                            </span>
                        )}
                    </ReceiptRow>

                    <ReceiptRow
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
                    </ReceiptRow>

                    <ReceiptRow
                        icon={<Icon name="schedule" />}
                        label={t.futureMovements.time}
                    >
                        {editing ? (
                            <TimeField
                                value={time}
                                onChange={setTime}
                                label={t.futureMovements.time}
                                compact
                            />
                        ) : (
                            formatTransactionTime(movement.date, formatLocale)
                        )}
                    </ReceiptRow>

                    <ReceiptRow
                        icon={<Icon name="account_balance" />}
                        label={t.futureMovements.account}
                        stacked={editing}
                    >
                        {editing ? (
                            <PickerField
                                label={t.futureMovements.account}
                                value={MOCK_ACCOUNTS[accountId]?.name ?? ''}
                                placeholder={t.addManual.select}
                                compact
                                onClick={() => setOpenPicker('account')}
                            />
                        ) : (
                            (MOCK_ACCOUNTS[movement.accountId]?.name ?? '—')
                        )}
                    </ReceiptRow>

                    <ReceiptRow
                        icon={<Icon name="sell" />}
                        label={t.futureMovements.category}
                        stacked={editing}
                    >
                        {editing ? (
                            <PickerField
                                label={t.futureMovements.category}
                                value={MOCK_CATEGORIES[categoryId]?.name ?? ''}
                                placeholder={t.addManual.select}
                                compact
                                onClick={() => setOpenPicker('category')}
                            />
                        ) : (
                            (MOCK_CATEGORIES[movement.categoryId]?.name ?? '—')
                        )}
                    </ReceiptRow>

                    <ReceiptRow
                        icon={<Icon name="notes" />}
                        label={t.futureMovements.description}
                        stacked
                    >
                        {editing ? (
                            <Textarea
                                value={description}
                                onChange={(event) =>
                                    setDescription(event.target.value)
                                }
                                rows={2}
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
                    </ReceiptRow>
                </div>
            </form>

            <OptionSheet
                open={openPicker === 'frequency'}
                onOpenChange={(open) => {
                    if (!open) setOpenPicker(null)
                }}
                title={t.futureMovements.frequency}
                options={FREQUENCY_OPTIONS.map((value) => ({
                    id: value,
                    label: frequencyLabel(value, t),
                }))}
                selected={frequency}
                onSelect={(id) => {
                    setFrequency(id as MockFrequency)
                    setOpenPicker(null)
                }}
            />

            <OptionSheet
                open={openPicker === 'account'}
                onOpenChange={(open) => {
                    if (!open) setOpenPicker(null)
                }}
                title={t.futureMovements.account}
                options={Object.entries(MOCK_ACCOUNTS).map(([id, account]) => ({
                    id,
                    label: account.name,
                }))}
                selected={accountId}
                onSelect={(id) => {
                    setAccountId(id)
                    setOpenPicker(null)
                }}
            />

            <OptionSheet
                open={openPicker === 'category'}
                onOpenChange={(open) => {
                    if (!open) setOpenPicker(null)
                }}
                title={t.futureMovements.category}
                options={Object.entries(MOCK_CATEGORIES).map(
                    ([id, category]) => ({ id, label: category.name }),
                )}
                selected={categoryId}
                onSelect={(id) => {
                    setCategoryId(id)
                    setOpenPicker(null)
                }}
            />

            <M3Dialog
                open={pendingScope !== null}
                onOpenChange={(open) => {
                    if (!open) setPendingScope(null)
                }}
                title={
                    pendingScope === 'delete'
                        ? t.futureMovements.deleteRecurring
                        : t.futureMovements.saveChanges
                }
                description={
                    pendingScope === 'delete'
                        ? t.futureMovements.scopeDeleteDescription(
                              movement.name,
                          )
                        : t.futureMovements.scopeEditDescription
                }
                actions={
                    <>
                        <DialogAction
                            label={t.futureMovements.cancel}
                            onPress={() => setPendingScope(null)}
                        />
                        <DialogAction
                            label={t.futureMovements.scopeOnlyThis}
                            destructive={pendingScope === 'delete'}
                            onPress={() => applyScope('only-this')}
                        />
                        <DialogAction
                            label={t.futureMovements.scopeAllFuture}
                            destructive={pendingScope === 'delete'}
                            onPress={() => applyScope('all-future')}
                        />
                    </>
                }
            />
        </>
    )
}

/**
 * A labelled row of the receipt, matching `ReceiptRow` in the Activity detail:
 * the label and its glyph on one side, the value on the other, stacking when
 * the value is an editor that needs the width.
 */
function ReceiptRow({
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
