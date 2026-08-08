import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import { Landmark, Plus } from 'lucide-react'
import { useMemo, useState } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { type Messages, useT } from '@/lib/i18n'
import {
    AccountDetailsSheet,
    type AccountSummary,
} from '@/pages/accounts/account-details-sheet'
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

    // Derive the open account from the live query so edits saved in the sheet
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
            error: t.accounts.createFailed,
        })
        await run
        setCreating(false)
    }

    return (
        <div className="flex flex-1 flex-col">
            <div className="flex items-center justify-end border-b px-4 py-2">
                <Button size="sm" onClick={() => setCreating(true)}>
                    <Plus data-icon="inline-start" />
                    {t.accounts.newAccount}
                </Button>
            </div>

            <div className="flex-1 p-4">
                {accounts === undefined ? (
                    <AccountsSkeleton />
                ) : accounts.length === 0 ? (
                    <EmptyState t={t} onCreate={() => setCreating(true)} />
                ) : (
                    <ul className="divide-y overflow-hidden rounded-md border bg-card">
                        {accounts.map((account) => (
                            <li key={account.id}>
                                <AccountTile
                                    id={account.id}
                                    name={account.name}
                                    icon={account.icon}
                                    color={account.color}
                                    onClick={() => setSelectedId(account.id)}
                                />
                            </li>
                        ))}
                    </ul>
                )}
            </div>

            <AccountFormDialog
                open={creating}
                onOpenChange={setCreating}
                onSubmit={handleCreate}
            />

            <AccountDetailsSheet
                account={selected}
                open={selectedId !== null}
                onOpenChange={(open) => {
                    if (!open) setSelectedId(null)
                }}
            />
        </div>
    )
}

function EmptyState({ t, onCreate }: { t: Messages; onCreate: () => void }) {
    return (
        <div className="flex flex-col items-center justify-center gap-4 py-16 text-center">
            <Landmark className="size-12 text-muted-foreground" />
            <div className="flex flex-col gap-1">
                <p className="font-medium">{t.accounts.emptyTitle}</p>
                <p className="text-sm text-muted-foreground">
                    {t.accounts.emptyDescription}
                </p>
            </div>
            <Button onClick={onCreate}>
                <Plus data-icon="inline-start" />
                {t.accounts.createAccount}
            </Button>
        </div>
    )
}

function AccountsSkeleton() {
    return (
        <div className="space-y-2">
            {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-16 w-full" />
            ))}
        </div>
    )
}
