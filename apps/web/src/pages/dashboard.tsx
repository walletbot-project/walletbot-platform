import { t } from '@wallet-bot/shared'
import { AccountBalances } from '@/components/dashboard/account-balances'
import { RecentTransactions } from '@/components/dashboard/recent-transactions'
import { SpendingByCategory } from '@/components/dashboard/spending-by-category'
import { SummaryCards } from '@/components/dashboard/summary-cards'
import { PageHeader } from '@/components/shared/page-header'

export function Dashboard() {
    return (
        <>
            <PageHeader title={t('dashboard.title')} />
            <div className="flex flex-col gap-6">
                <SummaryCards />
                <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
                    <AccountBalances />
                    <SpendingByCategory />
                </div>
                <RecentTransactions />
            </div>
        </>
    )
}
