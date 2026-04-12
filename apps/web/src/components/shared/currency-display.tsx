import { formatCurrency } from '@/lib/format'
import { cn } from '@/lib/utils'

interface CurrencyDisplayProps {
    cents: number
    currency: string
    className?: string
}

export function CurrencyDisplay({
    cents,
    currency,
    className,
}: CurrencyDisplayProps) {
    return (
        <span className={cn('tabular-nums', className)}>
            {formatCurrency(cents, currency)}
        </span>
    )
}
