import { api } from '@wallet-bot/backend/api'
import { recurrenceHorizon } from '@wallet-bot/shared'
import { Button, IconButton } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { type ReactNode, useState } from 'react'
import { toast } from 'sonner'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
import { useFormatLocale, useT } from '@/lib/i18n'
import { formatMoney } from '@/lib/money'
import { cn } from '@/lib/utils'
import {
    type ActivityTransaction,
    formatNumericDate,
    formatTransactionTime,
    signedAmountCents,
} from '../activity/helpers'

/**
 * One upcoming movement, presented the way `TransactionDetail` presents a past
 * one: the layout's occupant, headed by its own `AppBar`. `ListDetailLayout`
 * decides whether that lands in a sheet, a dialog or the split pane.
 *
 * An open-ended series can be topped up from here. Editing and deleting are
 * still absent, deliberately: either one has to say whether it means this
 * occurrence or this one and the ones after it, and wiring them to something
 * that silently touched a single row would be a worse answer than not
 * offering them yet.
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

    const accounts = useQuery(api.v1.accounts.queries.list, {
        includeArchived: true,
    })
    const categories = useQuery(api.v1.categories.queries.listActive)

    const rule = useQuery(api.v1.recurrences.queries.get, {
        recurrenceId: movement.recurrenceId,
    })
    const addOccurrences = useMutation(
        api.v1.recurrences.mutations.addOccurrences,
    )
    const [adding, setAdding] = useState(false)

    // Only an open-ended series can be topped up. One with an end date is
    // already complete, and running past a boundary the user set on purpose
    // would be editing the rule rather than extending it.
    const topUp =
        rule && rule.endDate === undefined
            ? recurrenceHorizon(
                  rule.frequency,
                  rule.dayInterval === undefined
                      ? undefined
                      : Number(rule.dayInterval),
              ).count
            : null

    const onAddMore = async (recurrenceId: string, count: number) => {
        setAdding(true)
        const pending = toast.loading(t.futureMovements.addingMore)
        try {
            await addOccurrences({ recurrenceId })
            toast.success(t.futureMovements.addedMore({ count }), {
                id: pending,
            })
        } catch {
            toast.error(t.futureMovements.addMoreFailed, { id: pending })
        } finally {
            setAdding(false)
        }
    }

    const account = accounts?.find((a) => a.id === movement.accountId)
    const category = categories?.find((c) => c.id === movement.categoryId)

    const cents = signedAmountCents(movement)
    const sign = cents < 0 ? '-' : cents > 0 ? '+' : ''

    return (
        <>
            <AppBar
                title={t.futureMovements.detail}
                leading={
                    <IconButton
                        aria-label={t.common.close}
                        onPress={onClose}
                        className="text-on-surface-variant"
                    >
                        <Icon name="close" />
                    </IconButton>
                }
            />

            <div className="flex flex-1 flex-col px-4 pb-8">
                <div className="flex flex-col items-center pt-2 pb-4">
                    <h2 className="text-xl font-bold">{movement.name}</h2>
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
                </div>

                <div className="divide-y divide-outline-variant">
                    <ReceiptRow
                        icon={<Icon name="calendar_month" />}
                        label={t.futureMovements.date}
                    >
                        {formatNumericDate(
                            new Date(Number(movement.date)),
                            formatLocale,
                        )}
                    </ReceiptRow>

                    <ReceiptRow
                        icon={<Icon name="schedule" />}
                        label={t.futureMovements.time}
                    >
                        {formatTransactionTime(movement.date, formatLocale)}
                    </ReceiptRow>

                    <ReceiptRow
                        icon={<Icon name="account_balance" />}
                        label={t.futureMovements.account}
                    >
                        {account?.name ?? '—'}
                    </ReceiptRow>

                    <ReceiptRow
                        icon={<Icon name="sell" />}
                        label={t.futureMovements.category}
                    >
                        {category?.name ?? '—'}
                    </ReceiptRow>

                    <ReceiptRow
                        icon={<Icon name="notes" />}
                        label={t.futureMovements.description}
                        stacked
                    >
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
                    </ReceiptRow>
                </div>

                {topUp !== null && rule ? (
                    <div className="flex flex-col items-stretch gap-2 pt-6">
                        <Button
                            type="button"
                            variant="filled"
                            isDisabled={adding}
                            onPress={() => void onAddMore(rule.id, topUp)}
                        >
                            {adding
                                ? t.futureMovements.addingMore
                                : t.futureMovements.addMore({ count: topUp })}
                        </Button>
                        <p className="m3-body-small text-center text-on-surface-variant">
                            {t.futureMovements.addMoreHint}
                        </p>
                    </div>
                ) : null}
            </div>
        </>
    )
}

/**
 * A labelled row of the receipt, matching `ReceiptRow` in the Activity detail:
 * the label and its glyph on one side, the value on the other.
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
