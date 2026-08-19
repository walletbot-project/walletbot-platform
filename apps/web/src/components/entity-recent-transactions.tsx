import { Button, CircularProgress } from 'actify'
import { transactionName, useFormatLocale, useT } from '@/lib/i18n'
import {
    type ActivityTransaction,
    formatTransactionTime,
    signedAmountCents,
    transactionTimeStatus,
} from '@/pages/activity/helpers'
import { TransactionRow } from '@/pages/activity/transaction-row'

/** Compact `day month` label, e.g. `27 may` / `May 27`. */
function shortDate(ms: number, locale: string): string {
    return new Intl.DateTimeFormat(locale, {
        day: 'numeric',
        month: 'short',
    }).format(new Date(ms))
}

type RecentTransaction = ActivityTransaction & { currency: string }

type EntityRecentTransactionsProps = {
    title: string
    viewAllLabel: string
    onViewAll: () => void
    /** `undefined` while loading. */
    transactions: readonly RecentTransaction[] | undefined
}

/**
 * The "últimas transacciones / últimos movimientos" section shared by the
 * account, category and tag details sheets: a header with a "ver todas" action
 * and the five most recent rows. Handles loading and empty states.
 */
export function EntityRecentTransactions({
    title,
    viewAllLabel,
    onViewAll,
    transactions,
}: EntityRecentTransactionsProps) {
    const t = useT()
    const formatLocale = useFormatLocale()
    return (
        <section className="mt-7 flex flex-col gap-2">
            <div className="flex items-center justify-between gap-2">
                <h3 className="m3-title-medium">{title}</h3>
                <Button variant="text" onPress={onViewAll}>
                    {viewAllLabel}
                </Button>
            </div>
            {transactions === undefined ? (
                <div className="flex justify-center py-6">
                    <CircularProgress isIndeterminate />
                </div>
            ) : transactions.length === 0 ? (
                <p className="m3-body-medium py-4 text-on-surface-variant">
                    {t.activity.noMovementsYet}
                </p>
            ) : (
                <div className="flex flex-col gap-2.5">
                    {transactions.map((transaction) => (
                        <TransactionRow
                            key={transaction.id}
                            title={transactionName(
                                transaction.name,
                                transaction.type,
                                t,
                            )}
                            amountCents={signedAmountCents(transaction)}
                            dateConfirmed={transaction.dateConfirmed}
                            timeLabel={formatTransactionTime(
                                transaction.date,
                                formatLocale,
                            )}
                            timeStatus={transactionTimeStatus(transaction)}
                            description={shortDate(
                                Number(transaction.date),
                                formatLocale,
                            )}
                            currency={transaction.currency}
                        />
                    ))}
                </div>
            )}
        </section>
    )
}
