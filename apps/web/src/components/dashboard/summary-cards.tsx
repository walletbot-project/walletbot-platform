import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { useQuery } from 'convex/react'
import {
    ArrowDownLeft,
    ArrowUpRight,
    TrendingDown,
    TrendingUp,
} from 'lucide-react'
import { CurrencyDisplay } from '@/components/shared/currency-display'
import { CardSkeleton } from '@/components/shared/loading-skeleton'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useUserSettings } from '@/hooks/use-user-settings'
import { firstOfMonthString, lastOfMonthString } from '@/lib/format'

export function SummaryCards() {
    const { settings } = useUserSettings()
    const summary = useQuery(api.transactions.queries.getTransactionSummary, {
        startDate: firstOfMonthString(),
        endDate: lastOfMonthString(),
    })

    if (summary === undefined) {
        return (
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
                <CardSkeleton />
                <CardSkeleton />
                <CardSkeleton />
            </div>
        )
    }

    const isPositiveFlow = summary.netFlowCents >= 0

    return (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <Card>
                <CardHeader className="flex flex-row items-center justify-between pb-2">
                    <CardTitle className="text-sm font-medium">
                        {t('dashboard.totalExpenses')}
                    </CardTitle>
                    <ArrowDownLeft className="size-4 text-red-600 dark:text-red-400" />
                </CardHeader>
                <CardContent>
                    <CurrencyDisplay
                        cents={summary.totalExpenseCents}
                        currency={settings.defaultCurrency}
                        className="text-2xl font-bold text-red-600 dark:text-red-400"
                    />
                </CardContent>
            </Card>

            <Card>
                <CardHeader className="flex flex-row items-center justify-between pb-2">
                    <CardTitle className="text-sm font-medium">
                        {t('dashboard.totalIncome')}
                    </CardTitle>
                    <ArrowUpRight className="size-4 text-green-600 dark:text-green-400" />
                </CardHeader>
                <CardContent>
                    <CurrencyDisplay
                        cents={summary.totalIncomeCents}
                        currency={settings.defaultCurrency}
                        className="text-2xl font-bold text-green-600 dark:text-green-400"
                    />
                </CardContent>
            </Card>

            <Card>
                <CardHeader className="flex flex-row items-center justify-between pb-2">
                    <CardTitle className="text-sm font-medium">
                        {t('dashboard.netFlow')}
                    </CardTitle>
                    {isPositiveFlow ? (
                        <TrendingUp className="size-4 text-green-600 dark:text-green-400" />
                    ) : (
                        <TrendingDown className="size-4 text-red-600 dark:text-red-400" />
                    )}
                </CardHeader>
                <CardContent>
                    <CurrencyDisplay
                        cents={summary.netFlowCents}
                        currency={settings.defaultCurrency}
                        className={`text-2xl font-bold ${isPositiveFlow ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}`}
                    />
                </CardContent>
            </Card>
        </div>
    )
}
