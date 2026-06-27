import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import {
    ArrowDownLeft,
    ArrowLeftRight,
    ArrowUpRight,
    Pencil,
    Scale,
    Tag,
    Wallet,
} from 'lucide-react'
import { type FormEvent, useState } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
    Sheet,
    SheetContent,
    SheetFooter,
    SheetHeader,
    SheetTitle,
} from '@/components/ui/sheet'
import { Skeleton } from '@/components/ui/skeleton'
import { Textarea } from '@/components/ui/textarea'
import type { ChatMessage } from '@/hooks/use-voice'
import { cn } from '@/lib/utils'

type ActionResultMessage = Extract<ChatMessage, { kind: 'action-result' }>

// ─────────────────────────────────────────────────────────────────────────────
// Public dispatcher
// ─────────────────────────────────────────────────────────────────────────────

export function ActionWidget({ message }: { message: ActionResultMessage }) {
    const { toolName, entityId } = message

    if (
        toolName === 'addExpense' ||
        toolName === 'addIncome' ||
        toolName === 'addTransfer' ||
        toolName === 'addBalanceAdjustment'
    ) {
        return <TransactionActionWidget entityId={entityId} />
    }
    if (toolName === 'createAccount') {
        return <AccountActionWidget entityId={entityId} />
    }
    return <CategoryActionWidget entityId={entityId} />
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction
// ─────────────────────────────────────────────────────────────────────────────

type TxnDoc = {
    id: string
    type: 'expense' | 'income' | 'transfer' | 'balance_adjustment'
    name: string
    description?: string | null
    date: bigint
    amount: bigint
    currency: string
    categoryId: string
    accountId: string
    toAccountId?: string
    status: 'pending' | 'cleared'
}

function TransactionActionWidget({ entityId }: { entityId: string }) {
    const txn = useQuery(api.transactions.queries.get, { id: entityId })
    const accounts = useQuery(api.accounts.queries.list, {
        includeArchived: false,
    })
    const [editOpen, setEditOpen] = useState(false)

    if (txn === undefined || accounts === undefined) return <ActionSkeleton />
    if (txn === null) return null

    const account = accounts.find((a) => a.id === txn.accountId)
    const toAccount =
        txn.toAccountId !== undefined
            ? accounts.find((a) => a.id === txn.toAccountId)
            : undefined

    const { Icon, iconCls, label } = txnTypeConfig(txn.type)
    const amountStr = `${centsToDecimalStr(txn.amount)} ${txn.currency}`
    const dateStr = epochToDDMMYYYY(txn.date)

    const locationStr =
        txn.type === 'transfer'
            ? `${account?.name ?? '?'} → ${toAccount?.name ?? '?'}`
            : (account?.name ?? '?')

    return (
        <>
            <ActionCard>
                <div className={cn('rounded-full p-1.5', iconCls.bg)}>
                    <Icon className={cn('size-4', iconCls.text)} />
                </div>
                <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">{txn.name}</p>
                    <p className="truncate text-xs text-muted-foreground">
                        {label} · {amountStr} · {locationStr} · {dateStr}
                    </p>
                </div>
                <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    className="shrink-0 gap-1.5"
                    onClick={() => setEditOpen(true)}
                >
                    <Pencil className="size-3.5" />
                    Editar
                </Button>
            </ActionCard>
            <Sheet open={editOpen} onOpenChange={setEditOpen}>
                <SheetContent side="right">
                    <TxnEditContent
                        txn={txn}
                        onClose={() => setEditOpen(false)}
                    />
                </SheetContent>
            </Sheet>
        </>
    )
}

function TxnEditContent({
    txn,
    onClose,
}: {
    txn: TxnDoc
    onClose: () => void
}) {
    const updateTxn = useMutation(api.transactions.mutations.update)
    const categories = useQuery(api.categories.queries.listActive)

    const [name, setName] = useState(txn.name)
    const [amount, setAmount] = useState(() => centsToDecimalStr(txn.amount))
    const [date, setDate] = useState(() => epochToDateStr(txn.date))
    const [categoryId, setCategoryId] = useState(txn.categoryId)
    const [description, setDescription] = useState(txn.description ?? '')
    const [status, setStatus] = useState(txn.status)

    const showAmount =
        txn.type === 'expense' ||
        txn.type === 'income' ||
        txn.type === 'transfer'
    const showCategory = txn.type === 'expense' || txn.type === 'income'
    const showStatus = txn.type !== 'balance_adjustment'

    const handleSubmit = async (e: FormEvent) => {
        e.preventDefault()
        const promise = updateTxn({
            id: txn.id,
            name: name.trim() || undefined,
            amount: showAmount ? decimalStrToCents(amount) : undefined,
            date: dateStrToEpoch(date),
            categoryId: showCategory ? categoryId || undefined : undefined,
            description: description.trim() || undefined,
            status: showStatus ? status : undefined,
        })
        toast.promise(promise, {
            loading: 'Guardando…',
            success: 'Transacción actualizada',
            error: 'Error al guardar',
        })
        await promise
        onClose()
    }

    return (
        <>
            <SheetHeader>
                <SheetTitle>Editar transacción</SheetTitle>
            </SheetHeader>
            <form
                id="txn-edit-form"
                onSubmit={handleSubmit}
                className="flex flex-col gap-4 overflow-y-auto px-4 py-2"
            >
                <EditField label="Nombre" htmlFor="txn-name">
                    <Input
                        id="txn-name"
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        required
                    />
                </EditField>

                {showAmount && (
                    <EditField label="Monto" htmlFor="txn-amount">
                        <Input
                            id="txn-amount"
                            inputMode="decimal"
                            value={amount}
                            onChange={(e) =>
                                setAmount(normalizeDecimal(e.target.value))
                            }
                            required
                        />
                    </EditField>
                )}

                <EditField label="Fecha" htmlFor="txn-date">
                    <Input
                        id="txn-date"
                        type="date"
                        value={date}
                        onChange={(e) => setDate(e.target.value)}
                        required
                    />
                </EditField>

                {showCategory && (
                    <EditField label="Categoría" htmlFor="txn-category">
                        <select
                            id="txn-category"
                            value={categoryId}
                            onChange={(e) => setCategoryId(e.target.value)}
                            className="h-9 w-full rounded-md border bg-transparent px-3 text-sm outline-none focus-visible:border-primary"
                        >
                            {categories === undefined ? (
                                <option>Cargando…</option>
                            ) : (
                                categories.map((c) => (
                                    <option key={c.id} value={c.id}>
                                        {c.name}
                                    </option>
                                ))
                            )}
                        </select>
                    </EditField>
                )}

                <EditField label="Descripción" htmlFor="txn-description">
                    <Textarea
                        id="txn-description"
                        value={description}
                        onChange={(e) => setDescription(e.target.value)}
                        rows={3}
                    />
                </EditField>

                {showStatus && (
                    <EditField label="Estado" htmlFor="txn-status">
                        <select
                            id="txn-status"
                            value={status}
                            onChange={(e) =>
                                setStatus(
                                    e.target.value as 'pending' | 'cleared',
                                )
                            }
                            className="h-9 w-full rounded-md border bg-transparent px-3 text-sm outline-none focus-visible:border-primary"
                        >
                            <option value="cleared">Confirmado</option>
                            <option value="pending">Pendiente</option>
                        </select>
                    </EditField>
                )}
            </form>
            <SheetFooter>
                <Button type="button" variant="outline" onClick={onClose}>
                    Cancelar
                </Button>
                <Button type="submit" form="txn-edit-form">
                    Guardar
                </Button>
            </SheetFooter>
        </>
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// Account
// ─────────────────────────────────────────────────────────────────────────────

type AccountDoc = {
    id: string
    name: string
    currency: string
    description?: string | null
}

function AccountActionWidget({ entityId }: { entityId: string }) {
    const account = useQuery(api.accounts.queries.get, { id: entityId })
    const [editOpen, setEditOpen] = useState(false)

    if (account === undefined) return <ActionSkeleton />
    if (account === null) return null

    return (
        <>
            <ActionCard>
                <div className="rounded-full bg-primary/10 p-1.5">
                    <Wallet className="size-4 text-primary" />
                </div>
                <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">
                        {account.name}
                    </p>
                    <p className="text-xs text-muted-foreground">
                        Cuenta creada · {account.currency}
                    </p>
                </div>
                <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    className="shrink-0 gap-1.5"
                    onClick={() => setEditOpen(true)}
                >
                    <Pencil className="size-3.5" />
                    Editar
                </Button>
            </ActionCard>
            <Sheet open={editOpen} onOpenChange={setEditOpen}>
                <SheetContent side="right">
                    <AccountEditContent
                        account={account}
                        onClose={() => setEditOpen(false)}
                    />
                </SheetContent>
            </Sheet>
        </>
    )
}

function AccountEditContent({
    account,
    onClose,
}: {
    account: AccountDoc
    onClose: () => void
}) {
    const updateAccount = useMutation(api.accounts.mutations.update)
    const [name, setName] = useState(account.name)
    const [description, setDescription] = useState(account.description ?? '')

    const handleSubmit = async (e: FormEvent) => {
        e.preventDefault()
        const promise = updateAccount({
            id: account.id,
            name: name.trim() || undefined,
            description: description.trim() || undefined,
        })
        toast.promise(promise, {
            loading: 'Guardando…',
            success: 'Cuenta actualizada',
            error: 'Error al guardar',
        })
        await promise
        onClose()
    }

    return (
        <>
            <SheetHeader>
                <SheetTitle>Editar cuenta</SheetTitle>
            </SheetHeader>
            <form
                id="account-edit-form"
                onSubmit={handleSubmit}
                className="flex flex-col gap-4 overflow-y-auto px-4 py-2"
            >
                <EditField label="Nombre" htmlFor="account-name">
                    <Input
                        id="account-name"
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        required
                    />
                </EditField>
                <EditField label="Descripción" htmlFor="account-description">
                    <Textarea
                        id="account-description"
                        value={description}
                        onChange={(e) => setDescription(e.target.value)}
                        rows={3}
                    />
                </EditField>
            </form>
            <SheetFooter>
                <Button type="button" variant="outline" onClick={onClose}>
                    Cancelar
                </Button>
                <Button type="submit" form="account-edit-form">
                    Guardar
                </Button>
            </SheetFooter>
        </>
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// Category
// ─────────────────────────────────────────────────────────────────────────────

type CategoryDoc = {
    id: string
    name: string
    description?: string | null
}

function CategoryActionWidget({ entityId }: { entityId: string }) {
    const category = useQuery(api.categories.queries.get, { id: entityId })
    const [editOpen, setEditOpen] = useState(false)

    if (category === undefined) return <ActionSkeleton />
    if (category === null) return null

    return (
        <>
            <ActionCard>
                <div className="rounded-full bg-primary/10 p-1.5">
                    <Tag className="size-4 text-primary" />
                </div>
                <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">
                        {category.name}
                    </p>
                    <p className="text-xs text-muted-foreground">
                        Categoría creada
                    </p>
                </div>
                <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    className="shrink-0 gap-1.5"
                    onClick={() => setEditOpen(true)}
                >
                    <Pencil className="size-3.5" />
                    Editar
                </Button>
            </ActionCard>
            <Sheet open={editOpen} onOpenChange={setEditOpen}>
                <SheetContent side="right">
                    <CategoryEditContent
                        category={category}
                        onClose={() => setEditOpen(false)}
                    />
                </SheetContent>
            </Sheet>
        </>
    )
}

function CategoryEditContent({
    category,
    onClose,
}: {
    category: CategoryDoc
    onClose: () => void
}) {
    const updateCategory = useMutation(api.categories.mutations.update)
    const [name, setName] = useState(category.name)
    const [description, setDescription] = useState(category.description ?? '')

    const handleSubmit = async (e: FormEvent) => {
        e.preventDefault()
        const promise = updateCategory({
            id: category.id,
            name: name.trim() || undefined,
            description: description.trim() || undefined,
        })
        toast.promise(promise, {
            loading: 'Guardando…',
            success: 'Categoría actualizada',
            error: 'Error al guardar',
        })
        await promise
        onClose()
    }

    return (
        <>
            <SheetHeader>
                <SheetTitle>Editar categoría</SheetTitle>
            </SheetHeader>
            <form
                id="category-edit-form"
                onSubmit={handleSubmit}
                className="flex flex-col gap-4 overflow-y-auto px-4 py-2"
            >
                <EditField label="Nombre" htmlFor="category-name">
                    <Input
                        id="category-name"
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        required
                    />
                </EditField>
                <EditField label="Descripción" htmlFor="category-description">
                    <Textarea
                        id="category-description"
                        value={description}
                        onChange={(e) => setDescription(e.target.value)}
                        rows={3}
                    />
                </EditField>
            </form>
            <SheetFooter>
                <Button type="button" variant="outline" onClick={onClose}>
                    Cancelar
                </Button>
                <Button type="submit" form="category-edit-form">
                    Guardar
                </Button>
            </SheetFooter>
        </>
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared UI helpers
// ─────────────────────────────────────────────────────────────────────────────

function ActionCard({ children }: { children: React.ReactNode }) {
    return (
        <div className="flex justify-center">
            <div className="flex w-full max-w-[92%] items-center gap-3 rounded-lg border bg-card px-3 py-2.5 text-sm">
                {children}
            </div>
        </div>
    )
}

function ActionSkeleton() {
    return (
        <div className="flex justify-center">
            <div className="flex w-full max-w-[92%] items-center gap-3 rounded-lg border bg-card px-3 py-2.5">
                <Skeleton className="size-7 rounded-full" />
                <div className="flex-1 space-y-1.5">
                    <Skeleton className="h-3 w-32" />
                    <Skeleton className="h-3 w-48" />
                </div>
            </div>
        </div>
    )
}

function EditField({
    label,
    htmlFor,
    children,
}: {
    label: string
    htmlFor: string
    children: React.ReactNode
}) {
    return (
        <div className="flex flex-col gap-1.5">
            <Label htmlFor={htmlFor}>{label}</Label>
            {children}
        </div>
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// Pure helpers
// ─────────────────────────────────────────────────────────────────────────────

type TxnType = 'expense' | 'income' | 'transfer' | 'balance_adjustment'

function txnTypeConfig(type: TxnType) {
    switch (type) {
        case 'expense':
            return {
                Icon: ArrowDownLeft,
                iconCls: {
                    bg: 'bg-red-100 dark:bg-red-900/30',
                    text: 'text-red-600 dark:text-red-400',
                },
                label: 'Gasto',
            }
        case 'income':
            return {
                Icon: ArrowUpRight,
                iconCls: {
                    bg: 'bg-green-100 dark:bg-green-900/30',
                    text: 'text-green-600 dark:text-green-400',
                },
                label: 'Ingreso',
            }
        case 'transfer':
            return {
                Icon: ArrowLeftRight,
                iconCls: {
                    bg: 'bg-blue-100 dark:bg-blue-900/30',
                    text: 'text-blue-600 dark:text-blue-400',
                },
                label: 'Transferencia',
            }
        case 'balance_adjustment':
            return {
                Icon: Scale,
                iconCls: {
                    bg: 'bg-violet-100 dark:bg-violet-900/30',
                    text: 'text-violet-600 dark:text-violet-400',
                },
                label: 'Ajuste de saldo',
            }
    }
}

function epochToDateStr(epoch: bigint): string {
    const d = new Date(Number(epoch))
    const y = d.getFullYear()
    const m = String(d.getMonth() + 1).padStart(2, '0')
    const day = String(d.getDate()).padStart(2, '0')
    return `${y}-${m}-${day}`
}

function epochToDDMMYYYY(epoch: bigint): string {
    const d = new Date(Number(epoch))
    const day = String(d.getDate()).padStart(2, '0')
    const m = String(d.getMonth() + 1).padStart(2, '0')
    return `${day}/${m}/${d.getFullYear()}`
}

function dateStrToEpoch(str: string): bigint {
    return BigInt(new Date(`${str}T00:00:00`).getTime())
}

function centsToDecimalStr(cents: bigint): string {
    return (Number(cents) / 100).toFixed(2)
}

function decimalStrToCents(str: string): bigint {
    const n = parseFloat(str.replace(',', '.'))
    if (!Number.isFinite(n)) return 0n
    return BigInt(Math.round(n * 100))
}

function normalizeDecimal(value: string): string {
    let hasSep = false
    return Array.from(value)
        .filter((c) => {
            if (/\d/.test(c)) return true
            if ((c === '.' || c === ',') && !hasSep) {
                hasSep = true
                return true
            }
            return false
        })
        .join('')
}
