import { api } from '@wallet-bot/backend/api'
import { Button, IconButton } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useMemo, useState } from 'react'
import { toast } from 'sonner'
import { AppBar } from '@/components/m3/app-bar'
import { DividedView } from '@/components/m3/divided-view'
import { Icon } from '@/components/m3/icon'
import { StateMessage } from '@/components/m3/state-message'
import { Skeleton } from '@/components/ui/skeleton'
import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import { type Messages, useT } from '@/lib/i18n'
import {
    AccountDetail,
    type AccountSummary,
} from '@/pages/accounts/account-detail'
import { accountErrorMessage } from '@/pages/accounts/account-errors'
import {
    AccountFormDialog,
    type AccountFormValue,
} from '@/pages/accounts/account-form-dialog'
import { AccountTile } from '@/pages/accounts/account-tile'

function newId() {
    return `${Date.now()}${Math.random().toString(36).slice(2, 8)}`
}

export function Accounts() {
    const t = useT()
    const accounts = useQuery(api.v1.accounts.queries.listActive)
    const createAccount = useMutation(api.v1.accounts.mutations.create)
    const createBalanceAdjustment = useMutation(
        api.v1.transactions.mutations.createBalanceAdjustment,
    )

    const [creating, setCreating] = useState(false)
    const [selectedId, setSelectedId] = useState<string | null>(null)

    // Derive the open account from the live query so edits saved in the detail
    // are reflected immediately (a stored snapshot would go stale on save).
    const selected: AccountSummary | null = useMemo(() => {
        if (selectedId === null || accounts === undefined) return null
        const account = accounts.find((a) => a.id === selectedId)
        return account
            ? {
                  id: account.id,
                  name: account.name,
                  currency: account.currency,
                  color: account.color,
                  icon: account.icon,
              }
            : null
    }, [accounts, selectedId])

    const handleCreate = async (value: AccountFormValue) => {
        const id = newId()
        const run = (async () => {
            await createAccount({
                id,
                name: value.name,
                currency: value.currency,
                color: value.color,
                icon: value.icon,
            })
            if (value.initialBalanceCents !== null) {
                await createBalanceAdjustment({
                    id: newId(),
                    accountId: id,
                    balanceAfter: BigInt(value.initialBalanceCents),
                    dateConfirmed: true,
                })
            }
        })()
        toast.promise(run, {
            loading: t.accounts.creating,
            success: t.accounts.created,
            error: (error) =>
                accountErrorMessage(error, t, t.accounts.createFailed),
        })
        await run
        setCreating(false)
    }

    const list = (
        <>
            <AppBar
                title={t.nav.accounts}
                actions={
                    <IconButton
                        aria-label={t.accounts.newAccount}
                        onPress={() => setCreating(true)}
                        className="text-on-surface-variant"
                    >
                        <Icon name="add" />
                    </IconButton>
                }
            />
            <div className="min-h-0 flex-1 overflow-y-auto">
                {accounts === undefined ? (
                    <AccountsSkeleton />
                ) : accounts.length === 0 ? (
                    <EmptyState t={t} onCreate={() => setCreating(true)} />
                ) : (
                    <div
                        className="flex flex-col px-4 pb-24"
                        style={{ gap: GROUP_SPACING }}
                    >
                        {accounts.map((account, index) => (
                            <AccountTile
                                key={account.id}
                                id={account.id}
                                name={account.name}
                                icon={account.icon}
                                color={account.color}
                                radius={groupedRadius(index, accounts.length)}
                                onClick={() => setSelectedId(account.id)}
                            />
                        ))}
                    </div>
                )}
            </div>
        </>
    )

    return (
        <>
            <DividedView
                list={list}
                detail={
                    selected ? (
                        <AccountDetail
                            account={selected}
                            onClose={() => setSelectedId(null)}
                        />
                    ) : null
                }
                detailTitle={selected?.name ?? t.nav.accounts}
                placeholder={
                    <div className="flex flex-1 items-center justify-center p-8">
                        <p className="m3-body-large max-w-xs text-center text-on-surface-variant">
                            {t.accounts.selectDetail}
                        </p>
                    </div>
                }
                onDismiss={() => setSelectedId(null)}
            />

            <AccountFormDialog
                open={creating}
                onOpenChange={setCreating}
                onSubmit={handleCreate}
            />
        </>
    )
}

function EmptyState({ t, onCreate }: { t: Messages; onCreate: () => void }) {
    return (
        <StateMessage
            icon="account_balance_wallet"
            title={t.accounts.emptyTitle}
            detail={t.accounts.emptyDescription}
            action={
                <Button variant="filled" onPress={onCreate}>
                    <Icon name="add" size={18} />
                    {t.accounts.createAccount}
                </Button>
            }
        />
    )
}

function AccountsSkeleton() {
    return (
        <div className="flex flex-col gap-group-seam px-4">
            {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-18 w-full rounded-lg" />
            ))}
        </div>
    )
}
