import { t } from '@wallet-bot/shared'
import { Plus } from 'lucide-react'
import { useState } from 'react'
import { PageHeader } from '@/components/shared/page-header'
import { TransactionFilters } from '@/components/transactions/transaction-filters'
import { TransactionFormDialog } from '@/components/transactions/transaction-form-dialog'
import { TransactionList } from '@/components/transactions/transaction-list'
import { Button } from '@/components/ui/button'

export function Transactions() {
    const [addOpen, setAddOpen] = useState(false)

    return (
        <>
            <PageHeader
                title={t('transactions.title')}
                actions={
                    <Button size="sm" onClick={() => setAddOpen(true)}>
                        <Plus className="size-4" />
                        {t('transactions.add')}
                    </Button>
                }
            />
            <div className="flex flex-col gap-4">
                <TransactionFilters />
                <TransactionList />
            </div>
            <TransactionFormDialog open={addOpen} onOpenChange={setAddOpen} />
        </>
    )
}
