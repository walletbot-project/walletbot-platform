import { api } from '@wallet-bot/backend/api'
import { t } from '@wallet-bot/shared'
import { useMutation, useQuery } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import { MoreHorizontal, Star, Wallet } from 'lucide-react'
import { useState } from 'react'
import { toast } from 'sonner'
import { ConfirmDialog } from '@/components/shared/confirm-dialog'
import { CurrencyDisplay } from '@/components/shared/currency-display'
import { EmptyState } from '@/components/shared/empty-state'
import { ListSkeleton } from '@/components/shared/loading-skeleton'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { useAccounts } from '@/hooks/use-accounts'
import { AccountFormDialog } from './account-form-dialog'

type Account = FunctionReturnType<
    typeof api.accounts.queries.listAccounts
>[number]

export function AccountList() {
    const { accounts, isLoading } = useAccounts()
    const balances = useQuery(api.transactions.queries.getAllAccountBalances)
    const setDefault = useMutation(api.accounts.mutations.setDefaultAccount)
    const deleteAccount = useMutation(api.accounts.mutations.deleteAccount)

    const [editAccount, setEditAccount] = useState<Account | null>(null)
    const [deleteTarget, setDeleteTarget] = useState<Account | null>(null)

    if (isLoading) return <ListSkeleton count={3} />

    if (accounts.length === 0) {
        return <EmptyState icon={Wallet} title={t('accounts.empty')} />
    }

    const getBalance = (accountId: string) =>
        balances?.find((b) => b.accountId === accountId)

    return (
        <>
            <div className="flex flex-col gap-2">
                {accounts.map((account) => {
                    const balance = getBalance(account._id)
                    return (
                        <div
                            key={account._id}
                            className="flex items-center gap-3 rounded-lg border p-3"
                        >
                            <span className="text-lg">{account.icon}</span>
                            <div className="flex-1">
                                <div className="flex items-center gap-2">
                                    <span className="text-sm font-medium">
                                        {account.name}
                                    </span>
                                    <Badge
                                        variant="secondary"
                                        className="text-[10px]"
                                    >
                                        {account.type}
                                    </Badge>
                                    {account.isDefault && (
                                        <Star className="size-3 fill-amber-400 text-amber-400" />
                                    )}
                                </div>
                                <span className="text-xs text-muted-foreground">
                                    {account.currency}
                                </span>
                            </div>
                            {balance && (
                                <CurrencyDisplay
                                    cents={balance.balanceCents}
                                    currency={balance.currency}
                                    className="text-sm font-semibold"
                                />
                            )}
                            <DropdownMenu>
                                <DropdownMenuTrigger
                                    render={
                                        <Button
                                            variant="ghost"
                                            size="icon-xs"
                                        />
                                    }
                                >
                                    <MoreHorizontal className="size-4" />
                                </DropdownMenuTrigger>
                                <DropdownMenuContent align="end">
                                    <DropdownMenuItem
                                        onClick={() => setEditAccount(account)}
                                    >
                                        {t('common.edit')}
                                    </DropdownMenuItem>
                                    {!account.isDefault && (
                                        <DropdownMenuItem
                                            onClick={async () => {
                                                await setDefault({
                                                    accountId: account._id,
                                                })
                                                toast.success(
                                                    t('toast.success.updated'),
                                                )
                                            }}
                                        >
                                            {t('accounts.setDefault')}
                                        </DropdownMenuItem>
                                    )}
                                    <DropdownMenuItem
                                        className="text-destructive"
                                        onClick={() => setDeleteTarget(account)}
                                    >
                                        {t('common.delete')}
                                    </DropdownMenuItem>
                                </DropdownMenuContent>
                            </DropdownMenu>
                        </div>
                    )
                })}
            </div>

            <AccountFormDialog
                open={editAccount !== null}
                onOpenChange={(open) => !open && setEditAccount(null)}
                account={editAccount ?? undefined}
            />

            <ConfirmDialog
                open={deleteTarget !== null}
                onOpenChange={(open) => !open && setDeleteTarget(null)}
                title={t('accounts.delete')}
                description={t('accounts.delete.confirm')}
                confirmLabel={t('common.delete')}
                onConfirm={async () => {
                    if (!deleteTarget) return
                    try {
                        await deleteAccount({ accountId: deleteTarget._id })
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
        </>
    )
}
