import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import { Check, Pencil, SlidersHorizontal, Trash2 } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { AccountIcon } from '@/components/account-icon'
import { ColorSwatches } from '@/components/color-swatches'
import { EntityRecentTransactions } from '@/components/entity-recent-transactions'
import { IconPicker } from '@/components/icon-picker'
import { Button } from '@/components/ui/button'
import {
    Dialog,
    DialogContent,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Sheet, SheetContent, SheetTitle } from '@/components/ui/sheet'
import { ACCOUNT_ICONS } from '@/lib/account-icons'
import {
    ACCOUNT_DEFAULT_COLOR,
    COLOR_OPTIONS,
    normalizeColor,
} from '@/lib/entity-colors'
import { formatMoney } from '@/lib/money'
import { cn } from '@/lib/utils'

export type AccountSummary = {
    id: string
    name: string
    currency: string
    color?: string
    icon?: string
}

export function AccountDetailsSheet({
    account,
    open,
    onOpenChange,
}: {
    account: AccountSummary | null
    open: boolean
    onOpenChange: (open: boolean) => void
}) {
    const navigate = useNavigate()
    const updateAccount = useMutation(api.accounts.mutations.update)
    const archiveAccount = useMutation(api.accounts.mutations.archive)
    const createBalanceAdjustment = useMutation(
        api.transactions.mutations.createBalanceAdjustment,
    )

    const accountId = account?.id ?? ''
    const balance = useQuery(
        api.transactions.queries.balance,
        account ? { accountId } : 'skip',
    )
    const recent = useQuery(
        api.accounts.queries.recentTransactions,
        account ? { id: accountId, limit: 5 } : 'skip',
    )

    const [editing, setEditing] = useState(false)
    const [saving, setSaving] = useState(false)
    const [name, setName] = useState('')
    const [color, setColor] = useState(ACCOUNT_DEFAULT_COLOR)
    const [icon, setIcon] = useState('wallet')

    const [adjustOpen, setAdjustOpen] = useState(false)
    const [adjustValue, setAdjustValue] = useState('')
    const [deleteOpen, setDeleteOpen] = useState(false)

    // Re-seed the editable identity only when a *different* account opens.
    // Keying on the id (not the object) keeps live query updates — e.g. the
    // refreshed values right after a save — from clobbering in-progress edits.
    const [seededId, setSeededId] = useState<string | null>(null)
    useEffect(() => {
        const id = account?.id ?? null
        if (id === seededId) return
        setSeededId(id)
        if (account) {
            setName(account.name)
            setColor(normalizeColor(account.color, ACCOUNT_DEFAULT_COLOR))
            setIcon(account.icon ?? 'wallet')
            setEditing(false)
        }
    }, [account, seededId])

    if (!account) return null

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
            toast.error('El nombre no puede estar vacío')
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
            loading: 'Guardando cuenta…',
            success: 'Cuenta guardada',
            error: 'No se pudo guardar la cuenta',
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
            toast.error('Ingresá un monto válido')
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
            loading: 'Ajustando saldo…',
            success: 'Saldo ajustado',
            error: 'No se pudo ajustar el saldo',
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
            loading: 'Eliminando cuenta…',
            success: 'Cuenta eliminada',
            error: 'No se pudo eliminar la cuenta',
        })
        try {
            await promise
            setDeleteOpen(false)
            onOpenChange(false)
        } finally {
            setSaving(false)
        }
    }

    const openAdjust = () => {
        setAdjustValue(cents !== null ? (cents / 100).toFixed(2) : '0.00')
        setAdjustOpen(true)
    }

    const viewAllTransactions = () => {
        onOpenChange(false)
        navigate('/activity', { state: { accountIds: [account.id] } })
    }

    return (
        <Sheet open={open} onOpenChange={onOpenChange}>
            <SheetContent side="right" className="w-full gap-0 p-0 sm:max-w-md">
                <SheetTitle className="sr-only">{account.name}</SheetTitle>
                <div className="flex flex-1 flex-col gap-3 overflow-y-auto p-4">
                    {/* Identity hero — color-washed icon + name. */}
                    <div
                        className="flex items-center gap-4 rounded-2xl p-5"
                        style={{ backgroundColor: `${accent}24` }}
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
                                className="flex size-14 shrink-0 items-center justify-center rounded-2xl"
                                style={{ backgroundColor: `${accent}47` }}
                            >
                                <AccountIcon
                                    name={account.icon}
                                    className="size-7"
                                    color={accent}
                                />
                            </span>
                        )}
                        {editing ? (
                            <Input
                                value={name}
                                onChange={(e) => setName(e.target.value)}
                                className="bg-background"
                                aria-label="Nombre"
                            />
                        ) : (
                            <span className="min-w-0 flex-1 truncate text-xl font-semibold">
                                {account.name}
                            </span>
                        )}
                    </div>

                    {editing ? (
                        <ColorSwatches
                            value={color}
                            onChange={setColor}
                            options={COLOR_OPTIONS}
                        />
                    ) : null}

                    {/* Balance hero. */}
                    <div className="flex items-start justify-between gap-3 rounded-2xl border bg-card p-5">
                        <div className="flex min-w-0 flex-col">
                            <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                                Saldo
                            </span>
                            <span
                                className={cn(
                                    'mt-1 truncate text-3xl font-semibold tabular-nums',
                                    cents !== null && cents < 0
                                        ? 'text-destructive'
                                        : 'text-foreground',
                                )}
                            >
                                {balance
                                    ? formatMoney(
                                          Number(balance.balance),
                                          balance.currency,
                                      )
                                    : '—'}
                            </span>
                        </div>
                        <span className="shrink-0 rounded-lg bg-muted px-3 py-1.5 text-sm text-muted-foreground">
                            {account.currency}
                        </span>
                    </div>

                    {/* Actions. */}
                    <div className="flex items-center gap-2">
                        <Button
                            variant="secondary"
                            className="flex-1"
                            onClick={openAdjust}
                            disabled={saving}
                        >
                            <SlidersHorizontal data-icon="inline-start" />
                            Ajustar saldo
                        </Button>
                        <Button
                            variant={editing ? 'default' : 'secondary'}
                            size="icon"
                            onClick={handleToggleEditing}
                            disabled={saving}
                            aria-label={editing ? 'Listo' : 'Editar'}
                        >
                            {editing ? <Check /> : <Pencil />}
                        </Button>
                        <Button
                            variant="destructive"
                            size="icon"
                            onClick={() => setDeleteOpen(true)}
                            disabled={saving}
                            aria-label="Eliminar"
                        >
                            <Trash2 />
                        </Button>
                    </div>

                    <EntityRecentTransactions
                        title="Últimas transacciones"
                        viewAllLabel="Ver todas"
                        onViewAll={viewAllTransactions}
                        transactions={recent}
                    />
                </div>
            </SheetContent>

            {/* Adjust-balance dialog. */}
            <Dialog open={adjustOpen} onOpenChange={setAdjustOpen}>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Ajustar saldo</DialogTitle>
                    </DialogHeader>
                    <Input
                        value={adjustValue}
                        onChange={(e) => setAdjustValue(e.target.value)}
                        inputMode="decimal"
                        autoFocus
                        aria-label="Nuevo saldo"
                    />
                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={() => setAdjustOpen(false)}
                            disabled={saving}
                        >
                            Cancelar
                        </Button>
                        <Button onClick={handleAdjust} disabled={saving}>
                            Guardar
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>

            {/* Delete confirmation. */}
            <Dialog open={deleteOpen} onOpenChange={setDeleteOpen}>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Eliminar cuenta</DialogTitle>
                    </DialogHeader>
                    <p className="text-sm text-muted-foreground">
                        ¿Seguro que querés eliminar "{account.name}"? Dejará de
                        aparecer en tus cuentas.
                    </p>
                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={() => setDeleteOpen(false)}
                            disabled={saving}
                        >
                            Cancelar
                        </Button>
                        <Button
                            variant="destructive"
                            onClick={handleDelete}
                            disabled={saving}
                        >
                            Eliminar
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </Sheet>
    )
}
