import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { useMutation } from 'convex/react'
import { toast } from 'sonner'
import { ConfirmDialog } from '@/components/shared/confirm-dialog'

interface DeleteTransactionDialogProps {
    open: boolean
    onOpenChange: (open: boolean) => void
    transactionId: string | undefined
}

export function DeleteTransactionDialog({
    open,
    onOpenChange,
    transactionId,
}: DeleteTransactionDialogProps) {
    const deleteTransaction = useMutation(
        api.transactions.mutations.deleteTransaction,
    )

    return (
        <ConfirmDialog
            open={open}
            onOpenChange={onOpenChange}
            title={t('transactions.delete')}
            description={t('transactions.delete.confirm')}
            confirmLabel={t('common.delete')}
            variant="destructive"
            onConfirm={async () => {
                if (!transactionId) return
                try {
                    await deleteTransaction({
                        transactionId: transactionId as Parameters<
                            typeof deleteTransaction
                        >[0]['transactionId'],
                    })
                    toast.success(t('toast.success.deleted'))
                } catch (err) {
                    toast.error(
                        err instanceof Error
                            ? err.message
                            : t('toast.error.generic'),
                    )
                }
            }}
        />
    )
}
