import { Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { currencyPrefix } from '@/lib/money'
import {
    type ActivityTransaction,
    signedAmountCents,
} from '@/pages/activity/helpers'
import { TransactionRow } from '@/pages/activity/transaction-row'

const SHORT_MONTHS = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
]

/** Compact `day month` label, e.g. `27 may`. */
function shortDate(ms: number): string {
    const d = new Date(ms)
    return `${d.getDate()} ${SHORT_MONTHS[d.getMonth()]}`
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
    return (
        <section className="flex flex-col gap-2">
            <div className="flex items-center justify-between gap-2">
                <h3 className="text-base font-medium">{title}</h3>
                <Button variant="ghost" size="sm" onClick={onViewAll}>
                    {viewAllLabel}
                </Button>
            </div>
            {transactions === undefined ? (
                <div className="flex justify-center py-6">
                    <Loader2 className="size-5 animate-spin text-muted-foreground" />
                </div>
            ) : transactions.length === 0 ? (
                <p className="py-4 text-sm text-muted-foreground">
                    Sin movimientos todavía
                </p>
            ) : (
                <div className="flex flex-col gap-2.5">
                    {transactions.map((t) => (
                        <TransactionRow
                            key={t.id}
                            title={t.name}
                            amountCents={signedAmountCents(t)}
                            dateConfirmed={t.dateConfirmed}
                            description={shortDate(Number(t.date))}
                            currencySymbol={currencyPrefix(t.currency).trim()}
                        />
                    ))}
                </div>
            )}
        </section>
    )
}
