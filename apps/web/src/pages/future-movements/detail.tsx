import { api } from '@wallet-bot/backend/api'
import { IconButton } from 'actify'
import { useQuery } from 'convex/react'
import type { ReactNode } from 'react'
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
 * Read-only for now, deliberately. Editing or deleting an occurrence has to
 * say whether it means this one or this one and the ones after it, and "the
 * ones after it" needs the recurrence rule that materialised them — which does
 * not exist yet. Wiring the actions to something that silently touched a
 * single row would be a worse answer than not offering them.
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
