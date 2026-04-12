import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { useQuery } from 'convex/react'
import { Wallet } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { CurrencyDisplay } from '@/components/shared/currency-display'
import { EmptyState } from '@/components/shared/empty-state'
import { ListSkeleton } from '@/components/shared/loading-skeleton'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

export function AccountBalances() {
    const balances = useQuery(api.transactions.queries.getAllAccountBalances)
    const navigate = useNavigate()

    return (
        <Card>
            <CardHeader>
                <CardTitle>{t('accounts.title')}</CardTitle>
            </CardHeader>
            <CardContent>
                {balances === undefined ? (
                    <ListSkeleton count={3} />
                ) : balances.length === 0 ? (
                    <EmptyState
                        icon={Wallet}
                        title={t('accounts.empty')}
                        action={{
                            label: t('accounts.add'),
                            onClick: () => navigate('/accounts'),
                        }}
                    />
                ) : (
                    <div className="flex flex-col gap-2">
                        {balances.map((b) => (
                            <div
                                key={b.accountId}
                                className="flex items-center gap-3 rounded-lg border p-3"
                            >
                                <span className="text-lg">{b.icon}</span>
                                <div className="flex-1">
                                    <div className="flex items-center gap-2">
                                        <span className="text-sm font-medium">
                                            {b.name}
                                        </span>
                                        <Badge
                                            variant="secondary"
                                            className="text-[10px]"
                                        >
                                            {b.type}
                                        </Badge>
                                    </div>
                                </div>
                                <CurrencyDisplay
                                    cents={b.balanceCents}
                                    currency={b.currency}
                                    className="text-sm font-semibold"
                                />
                            </div>
                        ))}
                    </div>
                )}
            </CardContent>
        </Card>
    )
}
