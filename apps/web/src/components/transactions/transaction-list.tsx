import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { usePaginatedQuery } from 'convex/react'
import type { GenericId } from 'convex/values'
import { ArrowLeftRight } from 'lucide-react'
import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { EmptyState } from '@/components/shared/empty-state'
import { ListSkeleton } from '@/components/shared/loading-skeleton'
import { Button } from '@/components/ui/button'
import { DeleteTransactionDialog } from './delete-transaction-dialog'
import { TransactionFormDialog } from './transaction-form-dialog'
import { TransactionListItem } from './transaction-list-item'
import type { Transaction } from './types'

export function TransactionList() {
    const [searchParams] = useSearchParams()
    const [editTx, setEditTx] = useState<Transaction | null>(null)
    const [deleteTx, setDeleteTx] = useState<Transaction | null>(null)

    const typeParam = searchParams.get('type')
    const type =
        typeParam === 'expense' ||
        typeParam === 'income' ||
        typeParam === 'transfer'
            ? typeParam
            : undefined

    const { results, status, loadMore, isLoading } = usePaginatedQuery(
        api.transactions.queries.listTransactions,
        {
            type,
            categoryId: (searchParams.get('category') ?? undefined) as
                | GenericId<'categories'>
                | undefined,
            accountId: (searchParams.get('account') ?? undefined) as
                | GenericId<'accounts'>
                | undefined,
            startDate: searchParams.get('from') ?? undefined,
            endDate: searchParams.get('to') ?? undefined,
        },
        { initialNumItems: 20 },
    )

    if (isLoading) return <ListSkeleton count={8} />

    if (results.length === 0) {
        return (
            <EmptyState
                icon={ArrowLeftRight}
                title={t('transactions.empty')}
                description="Add your first transaction or use the voice assistant."
            />
        )
    }

    return (
        <>
            <div className="flex flex-col gap-2">
                {results.map((tx) => (
                    <TransactionListItem
                        key={tx._id}
                        transaction={tx}
                        onClick={() => setEditTx(tx)}
                    />
                ))}
            </div>

            {status === 'CanLoadMore' && (
                <div className="mt-4 flex justify-center">
                    <Button variant="outline" onClick={() => loadMore(20)}>
                        Load more
                    </Button>
                </div>
            )}

            <TransactionFormDialog
                open={editTx !== null}
                onOpenChange={(open) => !open && setEditTx(null)}
                transaction={editTx ?? undefined}
                onDelete={() => {
                    if (editTx) {
                        setDeleteTx(editTx)
                        setEditTx(null)
                    }
                }}
            />

            <DeleteTransactionDialog
                open={deleteTx !== null}
                onOpenChange={(open) => !open && setDeleteTx(null)}
                transactionId={deleteTx?._id}
            />
        </>
    )
}
