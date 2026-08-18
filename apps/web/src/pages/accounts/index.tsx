import { api } from '@wallet-bot/backend/api'
import { Button, IconButton } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useMemo } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
import { ListDetailLayout } from '@/components/m3/list-detail-layout'
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
    AccountForm,
    type AccountFormValue,
} from '@/pages/accounts/account-form'
import { AccountTile } from '@/pages/accounts/account-tile'

function newId() {
    return `${Date.now()}${Math.random().toString(36).slice(2, 8)}`
}

/**
 * The accounts list. What is open beside it — nothing, the create form, or one
 * account's detail — is decided by the child route, never by local state, so it
 * survives reload, back/forward and any window resize.
 */
export function Accounts() {
    const t = useT()
    const navigate = useNavigate()
    const accounts = useQuery(api.v1.accounts.queries.listActive)

    const list = (
        <>
            <AppBar
                title={t.nav.accounts}
                actions={
                    <IconButton
                        aria-label={t.accounts.newAccount}
                        onPress={() => navigate('/accounts/new')}
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
                    <EmptyState
                        t={t}
                        onCreate={() => navigate('/accounts/new')}
                    />
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
                                onClick={() =>
                                    navigate(`/accounts/${account.id}`)
                                }
                            />
                        ))}
                    </div>
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
        close()
    }

    return <AccountForm onClose={close} onSubmit={handleCreate} />
}

/** `/accounts/:accountId` — one account's detail as the layout's occupant. */
export function AccountDetailRoute() {
    const t = useT()
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

    if (accounts === undefined) {
        return (
            <div className="flex flex-col gap-3 p-4">
                <Skeleton className="h-28 w-full rounded-2xl" />
                <Skeleton className="h-24 w-full rounded-2xl" />
            </div>
        )
    }

    if (account === null) {
        return (
            <StateMessage
                icon="search_off"
                tone="error"
                title={t.common.notFoundTitle}
                detail={t.common.notFoundDescription}
                action={
                    <Button
                        variant="filled"
                        onPress={() => navigate('/accounts')}
                    >
                        {t.common.backToList}
                    </Button>
                }
            />
        )
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
