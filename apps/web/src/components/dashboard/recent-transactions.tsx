import { api } from '@wallet-bot/backend/api'
import { type TranslationKey, t } from '@wallet-bot/shared'
import { useQuery } from 'convex/react'
import { ArrowLeftRight } from 'lucide-react'
import { Link } from 'react-router-dom'
import { CurrencyDisplay } from '@/components/shared/currency-display'
import { EmptyState } from '@/components/shared/empty-state'
import { ListSkeleton } from '@/components/shared/loading-skeleton'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useCategories } from '@/hooks/use-categories'
import { formatDateRelative, TX_TYPE_ICONS, txTypeColor } from '@/lib/format'
import { cn } from '@/lib/utils'

export function RecentTransactions() {
    const result = useQuery(api.transactions.queries.listTransactions, {
        paginationOpts: { numItems: 5, cursor: null },
    })
    const { flatCategories } = useCategories()

    return (
        <Card>
            <CardHeader className="flex flex-row items-center justify-between">
                <CardTitle>{t('dashboard.recentTransactions')}</CardTitle>
                <Button
                    variant="ghost"
                    size="sm"
                    render={<Link to="/transactions" />}
                >
                    View all
                </Button>
            </CardHeader>
            <CardContent>
                {result === undefined ? (
                    <ListSkeleton count={5} />
                ) : result.page.length === 0 ? (
                    <EmptyState
                        icon={ArrowLeftRight}
                        title={t('transactions.empty')}
                    />
                ) : (
                    <div className="flex flex-col gap-2">
                        {result.page.map((tx) => {
                            const Icon = TX_TYPE_ICONS[tx.type]
                            const cat = tx.categoryId
                                ? flatCategories.find(
                                      (c) => c._id === tx.categoryId,
                                  )
                                : null
                            const catName = cat
                                ? cat.isSystem
                                    ? t(cat.name as TranslationKey)
                                    : cat.name
                                : null

                            return (
                                <div
                                    key={tx._id}
                                    className="flex items-center gap-3 rounded-lg border p-3"
                                >
                                    <div
                                        className={cn(
                                            'flex size-8 items-center justify-center rounded-full',
                                            tx.type === 'expense'
                                                ? 'bg-red-100 dark:bg-red-900/30'
                                                : tx.type === 'income'
                                                  ? 'bg-green-100 dark:bg-green-900/30'
                                                  : 'bg-blue-100 dark:bg-blue-900/30',
                                        )}
                                    >
                                        <Icon
                                            className={cn(
                                                'size-4',
                                                txTypeColor(tx.type),
                                            )}
                                        />
                                    </div>
                                    <div className="flex-1">
                                        <div className="flex items-center gap-2">
                                            <span className="text-sm font-medium">
                                                {tx.description}
                                            </span>
                                            {catName && (
                                                <Badge
                                                    variant="secondary"
                                                    className="text-[10px]"
                                                >
                                                    {catName}
                                                </Badge>
                                            )}
                                        </div>
                                        <span className="text-xs text-muted-foreground">
                                            {formatDateRelative(tx.date)}
                                        </span>
                                    </div>
                                    <CurrencyDisplay
                                        cents={tx.amount}
                                        currency={tx.currency}
                                        className={cn(
                                            'text-sm font-semibold',
                                            txTypeColor(tx.type),
                                        )}
                                    />
                                </div>
                            )
                        })}
                    </div>
                )}
            </CardContent>
        </Card>
    )
}
