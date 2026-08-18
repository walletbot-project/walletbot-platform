import { Skeleton } from '@/components/ui/skeleton'
import { useFormatLocale, useT } from '@/lib/i18n'
import { formatMoney } from '@/lib/money'

export type SpendEntry = { currency: string; cents: number }

/**
 * The "gastado este mes" figure: the dominant currency shown big, with a small
 * note when the entity mixes currencies. Mirrors the native spend hero.
 */
export function MonthlySpend({ spend }: { spend: SpendEntry[] | undefined }) {
    const t = useT()
    const formatLocale = useFormatLocale()
    if (spend === undefined) {
        return <Skeleton className="h-9 w-40" />
    }
    if (spend.length === 0) {
        return (
            <p className="text-base font-medium text-muted-foreground">
                {t.insights.noSpendThisMonth}
            </p>
        )
    }
    const [top, ...rest] = spend
    return (
        <div className="flex flex-col">
            <span className="truncate text-3xl font-semibold tabular-nums">
                {formatMoney(top.cents, top.currency, formatLocale)}
            </span>
            {rest.length > 0 ? (
                <span className="mt-1 text-xs text-muted-foreground">
                    {t.insights.otherCurrencies({ count: rest.length })}
                </span>
            ) : null}
        </div>
    )
}
