import { Skeleton } from '@/components/ui/skeleton'
import { useFormatLocale, useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'
import { formatAmount, type MonthlyAggregates } from './helpers'

type ActivitySummaryCardProps = {
    aggregates: MonthlyAggregates | undefined
}

/** Income / expenses / balance for the current month. Matches the native card. */
export function ActivitySummaryCard({ aggregates }: ActivitySummaryCardProps) {
    const t = useT()
    return (
        <div className="grid grid-cols-3 gap-4 rounded-xl border border-primary/40 bg-primary/5 px-5 py-4">
            <SummaryColumn
                label={t.activity.summaryIncome}
                cents={aggregates?.incomeCents}
                valueClassName="text-green-600 dark:text-green-500"
            />
            <SummaryColumn
                label={t.activity.summaryExpenses}
                cents={aggregates?.expensesCents}
                valueClassName="text-destructive"
            />
            <SummaryColumn
                label={t.activity.summaryBalance}
                cents={aggregates?.balanceCents}
                valueClassName="text-foreground"
            />
        </div>
    )
}

type SummaryColumnProps = {
    label: string
    cents: number | undefined
    valueClassName: string
}

function SummaryColumn({ label, cents, valueClassName }: SummaryColumnProps) {
    const formatLocale = useFormatLocale()
    return (
        <div className="flex flex-col gap-1.5">
            <span className="text-sm font-semibold text-foreground">
                {label}
            </span>
            {cents === undefined ? (
                <Skeleton className="h-6 w-20" />
            ) : (
                <span
                    className={cn(
                        'text-lg font-semibold tabular-nums',
                        valueClassName,
                    )}
                >
                    {formatAmount(cents, formatLocale)}
                </span>
            )}
        </div>
    )
}
