import { api } from '@wallet-bot/backend/api'
import { compareByPosition } from '@wallet-bot/shared'
import { Button, IconButton } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { DetailNotFound, DetailSkeleton } from '@/components/detail-fallbacks'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
import { ListDetailLayout } from '@/components/m3/list-detail-layout'
import { StateMessage } from '@/components/m3/state-message'
import { SortableList } from '@/components/sortable-list'
import { Skeleton } from '@/components/ui/skeleton'
import { useOccurrenceCutoff } from '@/hooks/use-occurrence-cutoff'
import { type Messages, useT } from '@/lib/i18n'
import { newId } from '@/lib/new-id'
import { applyReorder } from '@/lib/ordering'
import {
    AccountDetail,
    type AccountSummary,
} from '@/pages/accounts/account-detail'
import { accountErrorMessage } from '@/pages/accounts/account-errors'
import {
    AccountForm,
    type AccountFormValue,
} from '@/pages/accounts/account-form'
import { AccountTile } from '@/pages/accounts/account-tile'

/**
 * The accounts list. What is open beside it — nothing, the create form, or one
 * account's detail — is decided by the child route, never by local state, so it
 * survives reload, back/forward and any window resize.
 */
export function Accounts() {
    const t = useT()
    const navigate = useNavigate()
    const accounts = useQuery(api.v1.accounts.queries.listActive)
    // Reorder mode, like the home dashboard's edit mode: a mode of this list,
    // not something open beside it, so it stays out of the URL.
    const [editing, setEditing] = useState(false)
    // Optimistic, so a dropped row stays where it landed; Convex rolls the
    // patch back by itself if the mutation fails.
    const reorder = useMutation(
        api.v1.accounts.mutations.reorder,
    ).withOptimisticUpdate((localStore, args) => {
        const current = localStore.getQuery(
            api.v1.accounts.queries.listActive,
            {},
        )
        if (!current) return
        localStore.setQuery(
            api.v1.accounts.queries.listActive,
            {},
            applyReorder(current, args.ids, compareByPosition),
        )
    })
    const canReorder = (accounts?.length ?? 0) > 1

    const list = (
        <>
            <AppBar
                title={t.nav.accounts}
                actions={
                    editing ? (
                        <IconButton
                            aria-label={t.common.done}
                            onPress={() => setEditing(false)}
                            className="text-on-surface-variant"
                        >
                            <Icon name="check" />
                        </IconButton>
                    ) : (
                        <>
                            {canReorder ? (
                                <IconButton
                                    aria-label={t.reorder.reorderAccounts}
                                    onPress={() => setEditing(true)}
                                    className="text-on-surface-variant"
                                >
                                    <Icon name="edit" />
                                </IconButton>
                            ) : null}
                            <IconButton
                                aria-label={t.accounts.newAccount}
                                onPress={() => navigate('/accounts/new')}
                                className="text-on-surface-variant"
                            >
                                <Icon name="add" />
                            </IconButton>
                        </>
                    )
                }
            />
            <div className="min-h-0 flex-1 overflow-y-auto">
                {accounts === undefined ? (
                    <AccountsSkeleton />
                ) : accounts.length === 0 ? (
                    <EmptyState
                        t={t}
                        onCreate={() => navigate('/accounts/new')}
                    />
                ) : (
                    <SortableList
                        className="px-4 pb-24"
                        items={accounts}
                        idOf={(account) => account.id}
                        nameOf={(account) => account.name}
                        editing={editing}
                        onReorder={(ids) => {
                            reorder({ ids }).catch(() =>
                                toast.error(t.reorder.accountsFailed),
                            )
                        }}
                        renderItem={(account, { radius, dragHandle }) => (
                            <AccountTile
                                id={account.id}
                                name={account.name}
                                icon={account.icon}
                                color={account.color}
                                radius={radius}
                                dragHandle={dragHandle}
                                // While reordering, rows only move.
                                onClick={
                                    editing
                                        ? undefined
                                        : () =>
                                              navigate(
                                                  `/accounts/${account.id}`,
                                              )
                                }
                            />
                        )}
                    />
                )}
            </div>
        </>
    )

    return (
        <ListDetailLayout
            list={list}
            closeTo="/accounts"
            detailTitle={t.accounts.accountDetails}
            placeholder={
                <div className="flex flex-1 items-center justify-center p-8">
                    <p className="m3-body-large max-w-xs text-center text-on-surface-variant">
                        {t.accounts.selectDetail}
                    </p>
                </div>
            }
        />
    )
}

/** `/accounts/new` — the create form as the layout's occupant. */
export function AccountCreateRoute() {
    const t = useT()
    const navigate = useNavigate()
    const createAccount = useMutation(api.v1.accounts.mutations.create)
    const createBalanceAdjustment = useMutation(
        api.v1.transactions.mutations.createBalanceAdjustment,
    )
    const asOfMs = useOccurrenceCutoff()

    const close = () => navigate('/accounts')

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
                    asOfMs,
                    // The canonical name native writes for an opening balance
                    // (apps/native/lib/data/repositories/account_repository.dart).
                    // Omitting it took the backend's `Ajuste de saldo` default,
                    // so the same action produced two different names depending
                    // on which client did it.
                    name: 'Balance inicial',
                })
            }
        })()
        toast.promise(run, {
            loading: t.accounts.creating,
            success: t.accounts.created,
            error: (error) =>
                accountErrorMessage(error, t, t.accounts.createFailed),
        })
        // The toast already reported the failure; swallowing it here keeps the
        // form open without an unhandled rejection.
        try {
            await run
        } catch {
            return
        }
        close()
    }

    return <AccountForm onClose={close} onSubmit={handleCreate} />
}

/** `/accounts/:accountId` — one account's detail as the layout's occupant. */
export function AccountDetailRoute() {
    const navigate = useNavigate()
    const { accountId } = useParams()
    const accounts = useQuery(api.v1.accounts.queries.listActive)

    const account: AccountSummary | null = useMemo(() => {
        if (accounts === undefined || accountId === undefined) return null
        const match = accounts.find((a) => a.id === accountId)
        return match
            ? {
                  id: match.id,
                  name: match.name,
                  currency: match.currency,
                  color: match.color,
                  icon: match.icon,
              }
            : null
    }, [accounts, accountId])

    if (accounts === undefined) return <DetailSkeleton />

    if (account === null) {
        return <DetailNotFound onBack={() => navigate('/accounts')} />
    }

    return (
        <AccountDetail
            account={account}
            onClose={() => navigate('/accounts')}
        />
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
