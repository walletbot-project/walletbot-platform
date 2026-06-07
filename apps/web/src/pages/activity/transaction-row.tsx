import { Check, HelpCircle } from 'lucide-react'
import { cn } from '@/lib/utils'
import { formatSignedAmount } from './helpers'

type TransactionRowProps = {
    title: string
    /** Signed cents: positive renders green with `+`, negative with `-`. */
    amountCents: number
    /** `true` → confirmed date (green check); `false` → estimated (amber help). */
    dateConfirmed: boolean
    description?: string | null
}

export function TransactionRow({
    title,
    amountCents,
    dateConfirmed,
    description,
}: TransactionRowProps) {
    const isPositive = amountCents > 0
    return (
        <div className="flex items-center gap-3 rounded-xl border bg-card px-4 py-3 shadow-xs">
            <DateCheckIcon dateConfirmed={dateConfirmed} />
            <div className="flex min-w-0 flex-1 flex-col">
                <span className="truncate text-sm font-medium text-foreground">
                    {title}
                </span>
                {description ? (
                    <span className="truncate text-xs text-muted-foreground">
                        {description}
                    </span>
                ) : null}
            </div>
            <span
                className={cn(
                    'shrink-0 text-sm font-semibold tabular-nums',
                    isPositive
                        ? 'text-green-600 dark:text-green-500'
                        : 'text-foreground',
                )}
            >
                {formatSignedAmount(amountCents)}
            </span>
        </div>
    )
}

function DateCheckIcon({ dateConfirmed }: { dateConfirmed: boolean }) {
    if (dateConfirmed) {
        return (
            <Check
                className="size-5 shrink-0 text-green-600 dark:text-green-500"
                aria-label="Fecha confirmada"
            />
        )
    }
    return (
        <HelpCircle
            className="size-5 shrink-0 text-amber-600 dark:text-amber-500"
            aria-label="Fecha estimada"
        />
    )
}
