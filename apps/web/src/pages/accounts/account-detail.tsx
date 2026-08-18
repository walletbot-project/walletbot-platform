import { api } from '@wallet-bot/backend/api'
import { Button, IconButton, TextField } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { AccountIcon } from '@/components/account-icon'
import { ColorSwatches } from '@/components/color-swatches'
import { EntityRecentTransactions } from '@/components/entity-recent-transactions'
import { IconPicker } from '@/components/icon-picker'
import { DetailPaneHeader } from '@/components/m3/detail-pane-header'
import { DialogAction, M3Dialog } from '@/components/m3/dialog'
import { Icon } from '@/components/m3/icon'
import { ACCOUNT_ICONS } from '@/lib/account-icons'
import {
    ACCOUNT_DEFAULT_COLOR,
    COLOR_OPTIONS,
    normalizeColor,
} from '@/lib/entity-colors'
import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import { useFormatLocale, useT } from '@/lib/i18n'
import { formatMoney } from '@/lib/money'
import { cn } from '@/lib/utils'
import { accountErrorMessage } from '@/pages/accounts/account-errors'

export type AccountSummary = {
    id: string
    name: string
    currency: string
    color?: string
    icon?: string
}

/**
 * An account's details, laid out like the native `AccountDetailsSheet`: a
 * color-washed identity hero joined by the grouped-card seam to the balance
 * hero, a row of actions, and the five most recent transactions.
 *
 * Presentation-agnostic — `ListDetailLayout` renders it inline in the split pane on
 * expanded windows and inside a modal bottom sheet everywhere else.
 */
export function AccountDetail({
    account,
    onClose,
}: {
    account: AccountSummary
    onClose: () => void
}) {
    const navigate = useNavigate()
    const t = useT()
    const formatLocale = useFormatLocale()
    const updateAccount = useMutation(api.v1.accounts.mutations.update)
    const archiveAccount = useMutation(api.v1.accounts.mutations.archive)
    const createBalanceAdjustment = useMutation(
        api.v1.transactions.mutations.createBalanceAdjustment,
    )

    const balance = useQuery(api.v1.transactions.queries.balance, {
        accountId: account.id,
    })
    const recent = useQuery(api.v1.accounts.queries.recentTransactions, {
        id: account.id,
        limit: 5,
    })

    const [editing, setEditing] = useState(false)
    const [saving, setSaving] = useState(false)
    const [name, setName] = useState(account.name)
    const [color, setColor] = useState(
        normalizeColor(account.color, ACCOUNT_DEFAULT_COLOR),
    )
    const [icon, setIcon] = useState(account.icon ?? 'wallet')

    const [adjustOpen, setAdjustOpen] = useState(false)
    const [adjustValue, setAdjustValue] = useState('')
    const [deleteOpen, setDeleteOpen] = useState(false)

    // Re-seed the editable identity only when a *different* account opens.
    // Keying on the id (not the object) keeps live query updates — e.g. the
    // refreshed values right after a save — from clobbering in-progress edits.
    const [seededId, setSeededId] = useState(account.id)
    useEffect(() => {
        if (account.id === seededId) return
        setSeededId(account.id)
        setName(account.name)
        setColor(normalizeColor(account.color, ACCOUNT_DEFAULT_COLOR))
        setIcon(account.icon ?? 'wallet')
        setEditing(false)
    }, [account, seededId])

    const accent = editing
        ? color
        : normalizeColor(account.color, ACCOUNT_DEFAULT_COLOR)
    const cents = balance ? Number(balance.balance) : null

    const handleToggleEditing = async () => {
        if (!editing) {
            setEditing(true)
            return
        }
        const trimmed = name.trim()
        if (!trimmed) {
            toast.error(t.common.nameCannotBeEmpty)
            return
        }
        setSaving(true)
        const promise = updateAccount({
            id: account.id,
            name: trimmed,
            color,
            icon,
        })
        toast.promise(promise, {
            loading: t.accounts.saving,
            success: t.accounts.saved,
            error: (error) =>
                accountErrorMessage(error, t, t.accounts.saveFailed),
        })
        try {
            await promise
            setEditing(false)
        } finally {
            setSaving(false)
        }
    }

    const handleAdjust = async () => {
        const parsed = Number.parseFloat(adjustValue.replace(',', '.'))
        if (Number.isNaN(parsed)) {
            toast.error(t.accounts.invalidAmount)
            return
        }
        setSaving(true)
        const id = `${Date.now()}${Math.random().toString(36).slice(2, 8)}`
        const promise = createBalanceAdjustment({
            id,
            accountId: account.id,
            balanceAfter: BigInt(Math.round(parsed * 100)),
            dateConfirmed: true,
        })
        toast.promise(promise, {
            loading: t.accounts.adjusting,
            success: t.accounts.adjusted,
            error: t.accounts.adjustFailed,
        })
        try {
            await promise
            setAdjustOpen(false)
        } finally {
            setSaving(false)
        }
    }

    const handleDelete = async () => {
        setSaving(true)
        const promise = archiveAccount({ id: account.id })
        toast.promise(promise, {
            loading: t.accounts.deleting,
            success: t.accounts.deleted,
            error: t.accounts.deleteFailed,
        })
        try {
            await promise
            setDeleteOpen(false)
            onClose()
        } finally {
            setSaving(false)
        }
    }

    const openAdjust = () => {
        setAdjustValue(cents !== null ? (cents / 100).toFixed(2) : '0.00')
        setAdjustOpen(true)
    }

    const viewAllTransactions = () => {
        onClose()
        navigate('/activity', { state: { accountIds: [account.id] } })
    }

    return (
        <div className="flex flex-col pb-6">
            <DetailPaneHeader
                title={t.accounts.accountDetails}
                onClose={onClose}
            />
            <div className="flex flex-col px-4">
                {/*
                 * Identity hero — tinted by the account's accent so the whole block
                 * carries the account color, joined to the balance hero by the
                 * grouped-card seam.
                 */}
                <div
                    className="flex items-center gap-4 p-5"
                    style={{
                        backgroundColor: `${accent}24`,
                        ...groupedRadius(0, 2),
                    }}
                >
                    {editing ? (
                        <IconPicker
                            icon={icon}
                            color={color}
                            onIconChange={setIcon}
                            icons={ACCOUNT_ICONS}
                        />
                    ) : (
                        <span
                            className="flex size-15 shrink-0 items-center justify-center rounded-[20px]"
                            style={{ backgroundColor: `${accent}47` }}
                        >
                            <AccountIcon
                                name={account.icon}
                                size={30}
                                color={accent}
                            />
                        </span>
                    )}
                    {editing ? (
                        <TextField
                            variant="outlined"
                            className="min-w-0 flex-1"
                            value={name}
                            onChange={setName}
                            aria-label={t.common.name}
                            label={t.common.name}
                        />
                    ) : (
                        <span className="m3-title-large min-w-0 flex-1 truncate font-semibold">
                            {account.name}
                        </span>
                    )}
                </div>

                {editing ? (
                    <div className="pt-3">
                        <ColorSwatches
                            value={color}
                            onChange={setColor}
                            options={COLOR_OPTIONS}
                        />
                    </div>
                ) : null}

                {/* Balance hero — the focal number; currency rides along as a pill. */}
                <div
                    className="flex items-start gap-3 bg-surface-container-high px-5 pt-4 pb-4.5"
                    style={{
                        marginTop: GROUP_SPACING,
                        ...groupedRadius(1, 2),
                    }}
                >
                    <div className="flex min-w-0 flex-1 flex-col">
                        <span className="m3-label-medium tracking-[0.8px] text-on-surface-variant">
                            {t.accounts.balance.toUpperCase()}
                        </span>
                        <span
                            className={cn(
                                'm3-display-small mt-1.5 truncate font-semibold tabular-nums',
                                cents !== null && cents < 0
                                    ? 'text-error'
                                    : 'text-on-surface',
                            )}
                        >
                            {balance
                                ? formatMoney(
                                      Number(balance.balance),
                                      balance.currency,
                                      formatLocale,
                                  )
                                : '—'}
                        </span>
                    </div>
                    <span className="m3-label-large shrink-0 rounded-[10px] bg-surface-container-highest px-3 py-1.5 text-on-surface-variant">
                        {account.currency}
                    </span>
                </div>

                {/* Actions: a prominent tonal "adjust balance" plus edit and delete. */}
                <div className="mt-3 flex items-center gap-2">
                    <Button
                        variant="tonal"
                        className="flex-1"
                        onPress={openAdjust}
                        isDisabled={saving}
                    >
                        <Icon name="tune" filled size={18} />
                        {t.accounts.adjustBalance}
                    </Button>
                    <IconButton
                        onPress={handleToggleEditing}
                        isDisabled={saving}
                        aria-label={editing ? t.common.done : t.common.edit}
                        className={cn(
                            'rounded-full',
                            editing
                                ? 'bg-primary-container text-on-primary-container'
                                : 'bg-secondary-container text-on-secondary-container',
                        )}
                    >
                        <Icon
                            name={editing ? 'check' : 'edit'}
                            filled={editing}
                        />
                    </IconButton>
                    <IconButton
                        onPress={() => setDeleteOpen(true)}
                        isDisabled={saving}
                        aria-label={t.common.delete}
                        className="rounded-full bg-error-container text-on-error-container"
                    >
                        <Icon name="delete" />
                    </IconButton>
                </div>

                <EntityRecentTransactions
                    title={t.accounts.lastTransactions}
                    viewAllLabel={t.accounts.viewAll}
                    onViewAll={viewAllTransactions}
                    transactions={recent}
                />

                {/* Adjust-balance dialog. */}
                <M3Dialog
                    open={adjustOpen}
                    onOpenChange={setAdjustOpen}
                    title={t.accounts.adjustBalance}
                    actions={
                        <>
                            <DialogAction
                                label={t.common.cancel}
                                onPress={() => setAdjustOpen(false)}
                                isDisabled={saving}
                            />
                            <DialogAction
                                label={t.common.save}
                                onPress={handleAdjust}
                                isDisabled={saving}
                            />
                        </>
                    }
                >
                    <TextField
                        variant="outlined"
                        className="w-full"
                        aria-label={t.accounts.newBalance}
                        label={t.accounts.newBalance}
                        value={adjustValue}
                        onChange={setAdjustValue}
                        inputMode="decimal"
                        autoFocus
                    />
                </M3Dialog>

                {/* Delete confirmation. */}
                <M3Dialog
                    open={deleteOpen}
                    onOpenChange={setDeleteOpen}
                    title={t.accounts.deleteTitle}
                    description={t.accounts.deleteConfirm({
                        name: account.name,
                    })}
                    actions={
                        <>
                            <DialogAction
                                label={t.common.cancel}
                                onPress={() => setDeleteOpen(false)}
                                isDisabled={saving}
                            />
                            <DialogAction
                                label={t.common.delete}
                                onPress={handleDelete}
                                isDisabled={saving}
                                destructive
                            />
                        </>
                    }
                />
            </div>
        </div>
    )
}
