import { api } from '@wallet-bot/backend/api'
import { type TranslationKey, t } from '@wallet-bot/shared'
import { useQuery } from 'convex/react'
import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { useCategories } from '@/hooks/use-categories'
import { useUserSettings } from '@/hooks/use-user-settings'
import {
    firstOfMonthString,
    formatCurrency,
    lastOfMonthString,
} from '@/lib/format'

export function SpendingByCategory() {
    const { settings } = useUserSettings()
    const { flatCategories } = useCategories()
    const summary = useQuery(api.transactions.queries.getTransactionSummary, {
        startDate: firstOfMonthString(),
        endDate: lastOfMonthString(),
    })

    if (summary === undefined) {
        return (
            <Card>
                <CardHeader>
                    <CardTitle>{t('dashboard.byCategory')}</CardTitle>
                </CardHeader>
                <CardContent className="flex items-center justify-center py-8">
                    <Skeleton className="size-40 rounded-full" />
                </CardContent>
            </Card>
        )
    }

    if (summary.byCategory.length === 0) {
        return (
            <Card>
                <CardHeader>
                    <CardTitle>{t('dashboard.byCategory')}</CardTitle>
                </CardHeader>
                <CardContent>
                    <p className="py-8 text-center text-sm text-muted-foreground">
                        No expenses this month
                    </p>
                </CardContent>
            </Card>
        )
    }

    const data = summary.byCategory.map((item) => {
        const cat = flatCategories.find((c) => c._id === item.categoryId)
        const name = cat
            ? cat.isSystem
                ? t(cat.name as TranslationKey)
                : cat.name
            : 'Uncategorized'
        const color = cat?.color ?? '#6b7280'
        return { name, value: item.cents, color }
    })

    return (
        <Card>
            <CardHeader>
                <CardTitle>{t('dashboard.byCategory')}</CardTitle>
            </CardHeader>
            <CardContent>
                <ResponsiveContainer width="100%" height={200}>
                    <PieChart>
                        <Pie
                            data={data}
                            dataKey="value"
                            nameKey="name"
                            cx="50%"
                            cy="50%"
                            innerRadius={50}
                            outerRadius={80}
                            paddingAngle={2}
                        >
                            {data.map((entry) => (
                                <Cell key={entry.name} fill={entry.color} />
                            ))}
                        </Pie>
                        <Tooltip
                            formatter={(value) =>
                                formatCurrency(
                                    Number(value),
                                    settings.defaultCurrency,
                                )
                            }
                        />
                    </PieChart>
                </ResponsiveContainer>
                <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1">
                    {data.map((entry) => (
                        <div
                            key={entry.name}
                            className="flex items-center gap-1.5 text-xs"
                        >
                            <div
                                className="size-2.5 rounded-full"
                                style={{ backgroundColor: entry.color }}
                            />
                            <span className="text-muted-foreground">
                                {entry.name}
                            </span>
                        </div>
                    ))}
                </div>
            </CardContent>
        </Card>
    )
}
