import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import {
    CalendarDays,
    Check,
    Clock3,
    FileText,
    HelpCircle,
    Pencil,
    Tags,
    Trash2,
    WalletCards,
    X,
} from 'lucide-react'
import { type FormEvent, type ReactNode, useId, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { AccountIcon } from '@/components/account-icon'
import { CategoryIcon } from '@/components/category-icon'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
    Dialog,
    DialogContent,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import {
    Sheet,
    SheetContent,
    SheetFooter,
    SheetHeader,
    SheetTitle,
} from '@/components/ui/sheet'
import { Skeleton } from '@/components/ui/skeleton'
import { Textarea } from '@/components/ui/textarea'
import {
    ACCOUNT_DEFAULT_COLOR,
    CATEGORY_DEFAULT_COLOR,
    normalizeColor,
} from '@/lib/entity-colors'
import { formatMoney } from '@/lib/money'
import { normalizeTagColor } from '@/lib/tag-colors'
import { cn } from '@/lib/utils'
import type {
    TransactionFilters,
    TransactionTimeStatus,
    TransactionTransferSide,
} from './helpers'

type Transaction = NonNullable<
    FunctionReturnType<typeof api.v1.transactions.queries.get>
>
type Account = FunctionReturnType<typeof api.v1.accounts.queries.list>[number]
type Category = FunctionReturnType<
    typeof api.v1.categories.queries.listActive
>[number]
type Tag = FunctionReturnType<typeof api.v1.tags.queries.listActive>[number]
type AccountBalance = FunctionReturnType<
    typeof api.v1.transactions.queries.balanceAroundTransaction
>

type TransactionDetailsSheetProps = {
    transactionId: string | null
    transferSide?: TransactionTransferSide
    open: boolean
    onOpenChange: (open: boolean) => void
    initialEditing?: boolean
    // When provided, the read-mode date/category/tag chips apply the filter in
    // place (used by the Activity page, which owns the filter state). Without
    // it, they deep-link to /activity via the router.
    onApplyFilter?: (filters: Partial<TransactionFilters>) => void
}

export function TransactionDetailsSheet({
    transactionId,
    transferSide,
    open,
    onOpenChange,
    initialEditing = false,
    onApplyFilter,
}: TransactionDetailsSheetProps) {
    const transaction = useQuery(
        api.v1.transactions.queries.get,
        open && transactionId ? { id: transactionId } : 'skip',
    )
    const accounts = useQuery(
        api.v1.accounts.queries.list,
        open ? { includeArchived: true } : 'skip',
    )
    const categories = useQuery(
        api.v1.categories.queries.listActive,
        open ? {} : 'skip',
    )
    const currentCategory = useQuery(
        api.v1.categories.queries.get,
        open && transaction?.categoryId
            ? { id: transaction.categoryId }
            : 'skip',
    )
    const tags = useQuery(api.v1.tags.queries.listActive, open ? {} : 'skip')

    const isLoading =
        transaction === undefined ||
        accounts === undefined ||
        categories === undefined ||
        (transaction !== undefined &&
            transaction !== null &&
            transaction.categoryId !== '' &&
            currentCategory === undefined) ||
        tags === undefined

    const categoryOptions =
        categories &&
        currentCategory &&
        !categories.some((category) => category.id === currentCategory.id)
            ? [...categories, currentCategory]
            : categories

    return (
        <Sheet open={open} onOpenChange={onOpenChange}>
            <SheetContent
                side="right"
                className="w-full gap-0 p-0 sm:max-w-lg"
                showCloseButton={false}
            >
                {isLoading ? (
                    <TransactionDetailsSkeleton />
                ) : transaction === null ? (
                    <div className="flex flex-1 items-center justify-center p-8 text-sm text-muted-foreground">
                        La actividad ya no existe
                    </div>
                ) : (
                    <TransactionDetailsContent
                        key={`${transaction.id}-${transaction.updatedAt}`}
                        transaction={transaction}
                        accounts={accounts}
                        categories={categoryOptions ?? categories}
                        tags={tags}
                        transferSide={transferSide}
                        initialEditing={initialEditing}
                        onApplyFilter={onApplyFilter}
                        onClose={() => onOpenChange(false)}
                    />
                )}
            </SheetContent>
        </Sheet>
    )
}

function TransactionDetailsContent({
    transaction,
    accounts,
    categories,
    tags,
    transferSide,
    initialEditing,
    onApplyFilter,
    onClose,
}: {
    transaction: Transaction
    accounts: Account[]
    categories: Category[]
    tags: Tag[]
    transferSide?: TransactionTransferSide
    initialEditing: boolean
    onApplyFilter?: (filters: Partial<TransactionFilters>) => void
    onClose: () => void
}) {
    const navigate = useNavigate()

    // Running balance of each involved account before/after this transaction.
    // Keyed off the saved account ids (not the edit-mode selection) since it
    // reflects the persisted ledger, and only surfaced in read mode.
    const sourceBalance = useQuery(
        api.v1.transactions.queries.balanceAroundTransaction,
        { transactionId: transaction.id, accountId: transaction.accountId },
    )
    const destBalance = useQuery(
        api.v1.transactions.queries.balanceAroundTransaction,
        transaction.type === 'transfer' && transaction.toAccountId
            ? {
                  transactionId: transaction.id,
                  accountId: transaction.toAccountId,
              }
            : 'skip',
    )

    // Apply a filter to the Activity list and dismiss the sheet. Prefer the
    // in-place callback (Activity owns the filter state); otherwise deep-link.
    const applyFilter = (filters: Partial<TransactionFilters>) => {
        if (onApplyFilter) {
            onApplyFilter(filters)
        } else {
            void navigate('/activity', { state: filters })
        }
        onClose()
    }
    const updateTransaction = useMutation(api.v1.transactions.mutations.update)
    const archiveTransaction = useMutation(
        api.v1.transactions.mutations.archive,
    )
    const tagTransaction = useMutation(api.v1.transactions.mutations.tag)
    const untagTransaction = useMutation(api.v1.transactions.mutations.untag)
    const formId = useId()

    const [editing, setEditing] = useState(initialEditing)
    const [saving, setSaving] = useState(false)
    const [deleteOpen, setDeleteOpen] = useState(false)
    const [name, setName] = useState(transaction.name)
    const [description, setDescription] = useState(
        transaction.description ?? '',
    )
    const [amount, setAmount] = useState(() =>
        centsToInput(displayAmount(transaction, transferSide)),
    )
    const [date, setDate] = useState(() => dateInputValue(transaction.date))
    const [time, setTime] = useState(() => timeInputValue(transaction.date))
    const [dateConfirmed, setDateConfirmed] = useState(
        transaction.dateConfirmed,
    )
    const [timeStatus, setTimeStatus] = useState<TransactionTimeStatus>(
        transaction.timeStatus ?? 'none',
    )
    const [dateTouched, setDateTouched] = useState(false)
    const [timeTouched, setTimeTouched] = useState(false)
    const [accountId, setAccountId] = useState(transaction.accountId)
    const [toAccountId, setToAccountId] = useState(
        transaction.toAccountId ?? '',
    )
    const [categoryId, setCategoryId] = useState(transaction.categoryId)
    const [selectedTagIds, setSelectedTagIds] = useState(
        () => new Set(transaction.tagIds),
    )

    const account = accounts.find((item) => item.id === accountId)
    const destinationAccount = accounts.find((item) => item.id === toAccountId)
    const category = categories.find((item) => item.id === categoryId)
    const categoryColor = normalizeColor(
        category?.color,
        CATEGORY_DEFAULT_COLOR,
    )
    const canEditAmount =
        transaction.type === 'income' ||
        transaction.type === 'expense' ||
        transaction.type === 'transfer'
    const canEditAccount = transaction.type !== 'balance_adjustment'
    const isTransfer = transaction.type === 'transfer'
    const hasSelectedTags = tags.some((tag) => selectedTagIds.has(tag.id))
    const timeNeedsAttention = timeStatus !== 'confirmed'
    const signedAmount = displaySignedAmount(transaction, transferSide)
    const displayCurrency =
        transferSide === 'destination'
            ? (transaction.toCurrency ?? transaction.currency)
            : transaction.currency

    const handleSubmit = async (event: FormEvent) => {
        event.preventDefault()
        const trimmedName = name.trim()
        if (!trimmedName) {
            toast.error('El nombre no puede estar vacío')
            return
        }
        if (!account) {
            toast.error('Elegí una cuenta')
            return
        }
        if (isTransfer && (!destinationAccount || accountId === toAccountId)) {
            toast.error('La cuenta origen y destino deben ser distintas')
            return
        }

        let parsedAmount: bigint | undefined
        if (canEditAmount) {
            const parsed = inputToCents(amount)
            if (parsed === null || parsed <= 0n) {
                toast.error('Ingresá un monto mayor a cero')
                return
            }
            parsedAmount = parsed
        }

        const temporalChanged = dateTouched || timeTouched
        const nextDate = temporalChanged
            ? localDateTimeEpoch(date, time)
            : undefined
        const originalTags = new Set(transaction.tagIds)
        const toAdd = [...selectedTagIds].filter(
            (tagId) => !originalTags.has(tagId),
        )
        const toRemove = [...originalTags].filter(
            (tagId) => !selectedTagIds.has(tagId),
        )

        setSaving(true)
        try {
            await updateTransaction({
                id: transaction.id,
                name: trimmedName,
                description: description.trim(),
                date: nextDate,
                dateConfirmed: dateTouched ? dateConfirmed : undefined,
                timeStatus: temporalChanged ? timeStatus : undefined,
                amount:
                    parsedAmount !== undefined && transferSide !== 'destination'
                        ? parsedAmount
                        : undefined,
                toAmount:
                    parsedAmount !== undefined && transferSide === 'destination'
                        ? parsedAmount
                        : undefined,
                accountId: canEditAccount ? accountId : undefined,
                toAccountId: isTransfer ? toAccountId : undefined,
                categoryId:
                    transaction.type !== 'balance_adjustment'
                        ? categoryId
                        : undefined,
            })
            if (toAdd.length > 0) {
                await tagTransaction({
                    transactionId: transaction.id,
                    tagIds: toAdd,
                })
            }
            if (toRemove.length > 0) {
                await untagTransaction({
                    transactionId: transaction.id,
                    tagIds: toRemove,
                })
            }
            toast.success('Actividad actualizada')
            setEditing(false)
        } catch (error) {
            toast.error(
                error instanceof Error
                    ? error.message
                    : 'No se pudo guardar la actividad',
            )
        } finally {
            setSaving(false)
        }
    }

    const handleDelete = async () => {
        setSaving(true)
        try {
            await archiveTransaction({ id: transaction.id })
            toast.success('Actividad eliminada')
            setDeleteOpen(false)
            onClose()
        } catch {
            toast.error('No se pudo eliminar la actividad')
        } finally {
            setSaving(false)
        }
    }

    return (
        <>
            <SheetHeader className="flex-row items-center border-b">
                <SheetTitle className="flex-1">
                    {editing ? 'Editar actividad' : 'Detalle'}
                </SheetTitle>
                {editing ? (
                    // Keep the edit button's space occupied. Besides avoiding
                    // header movement, this prevents the event that opened the
                    // editor from landing on another actionable control.
                    <span className="size-8 shrink-0" aria-hidden />
                ) : (
                    <Button
                        type="button"
                        variant="ghost"
                        size="icon-sm"
                        onClick={() => setEditing(true)}
                        aria-label="Editar"
                    >
                        <Pencil />
                    </Button>
                )}
                <Button
                    type="button"
                    variant="ghost"
                    size="icon-sm"
                    onClick={() => setDeleteOpen(true)}
                    disabled={saving}
                    aria-label="Eliminar"
                >
                    <Trash2 />
                </Button>
                <Button
                    type="button"
                    variant="ghost"
                    size="icon-sm"
                    onClick={onClose}
                    disabled={saving}
                    aria-label="Cerrar"
                >
                    <X />
                </Button>
            </SheetHeader>

            <form
                id={formId}
                onSubmit={(event) => void handleSubmit(event)}
                className="min-h-0 flex-1 overflow-y-auto p-4"
            >
                <div className="overflow-hidden rounded-2xl border bg-card shadow-xs">
                    <div className="flex flex-col items-center px-6 py-7 text-center">
                        <span
                            className="flex size-16 items-center justify-center rounded-full"
                            style={{ backgroundColor: `${categoryColor}29` }}
                        >
                            <CategoryIcon
                                name={category?.icon}
                                className="size-8"
                                color={categoryColor}
                            />
                        </span>
                        {editing ? (
                            <Input
                                value={name}
                                onChange={(event) =>
                                    setName(event.target.value)
                                }
                                className="mt-4 h-10 max-w-sm text-center text-lg font-bold"
                                aria-label="Nombre"
                                required
                            />
                        ) : (
                            <h2 className="mt-4 text-xl font-bold">
                                {transaction.name}
                            </h2>
                        )}

                        {editing && canEditAmount ? (
                            <Input
                                value={amount}
                                onChange={(event) =>
                                    setAmount(
                                        normalizeAmount(event.target.value),
                                    )
                                }
                                inputMode="decimal"
                                className="mt-3 h-11 max-w-52 text-center text-2xl font-bold"
                                aria-label="Monto"
                                required
                            />
                        ) : (
                            <p
                                className={cn(
                                    'mt-2 text-2xl font-bold tabular-nums',
                                    signedAmount > 0
                                        ? 'text-green-600 dark:text-green-500'
                                        : 'text-foreground',
                                )}
                            >
                                {formatMoney(signedAmount, displayCurrency)}
                            </p>
                        )}
                    </div>

                    <div className="mx-6 border-t border-dashed" />

                    <div className="divide-y px-6">
                        <ReceiptRow
                            icon={<FileText />}
                            label="Descripción"
                            stacked
                        >
                            {editing ? (
                                <Textarea
                                    value={description}
                                    onChange={(event) =>
                                        setDescription(event.target.value)
                                    }
                                    rows={3}
                                    placeholder="Sin descripción"
                                />
                            ) : transaction.description ? (
                                <span>{transaction.description}</span>
                            ) : null}
                        </ReceiptRow>

                        <ReceiptRow
                            icon={
                                dateConfirmed ? (
                                    <CalendarDays />
                                ) : (
                                    <HelpCircle />
                                )
                            }
                            label={dateConfirmed ? 'Fecha' : 'Fecha estimada'}
                            attention={!dateConfirmed}
                        >
                            {editing ? (
                                <Input
                                    type="date"
                                    value={date}
                                    onChange={(event) => {
                                        setDate(event.target.value)
                                        setDateConfirmed(true)
                                        setDateTouched(true)
                                    }}
                                    className="w-auto"
                                    required
                                />
                            ) : (
                                <button
                                    type="button"
                                    className="cursor-pointer"
                                    onClick={() =>
                                        applyFilter({
                                            dateFrom: new Date(
                                                Number(transaction.date),
                                            ),
                                            dateTo: new Date(
                                                Number(transaction.date),
                                            ),
                                        })
                                    }
                                >
                                    {formatDate(transaction.date)}
                                </button>
                            )}
                        </ReceiptRow>

                        <ReceiptRow
                            icon={
                                timeNeedsAttention ? <HelpCircle /> : <Clock3 />
                            }
                            label={
                                timeNeedsAttention
                                    ? 'Horario estimado'
                                    : 'Horario'
                            }
                            attention={timeNeedsAttention}
                        >
                            {editing ? (
                                <Input
                                    type="time"
                                    value={time}
                                    onChange={(event) => {
                                        setTime(event.target.value)
                                        setTimeStatus('confirmed')
                                        setTimeTouched(true)
                                    }}
                                    className="w-auto"
                                    required
                                />
                            ) : (
                                formatTime(transaction.date)
                            )}
                        </ReceiptRow>

                        <ReceiptRow
                            icon={
                                <AccountIcon
                                    name={account?.icon}
                                    className="size-4"
                                    color={normalizeColor(
                                        account?.color,
                                        ACCOUNT_DEFAULT_COLOR,
                                    )}
                                />
                            }
                            label={isTransfer ? 'Cuenta origen' : 'Cuenta'}
                            stacked
                        >
                            {editing && canEditAccount ? (
                                <AccountSelect
                                    value={accountId}
                                    accounts={accounts}
                                    excludedId={
                                        isTransfer ? toAccountId : undefined
                                    }
                                    onChange={setAccountId}
                                />
                            ) : (
                                <div className="space-y-1">
                                    <div>
                                        {account ? (
                                            <button
                                                type="button"
                                                className="cursor-pointer"
                                                onClick={() =>
                                                    applyFilter({
                                                        accountIds: [
                                                            account.id,
                                                        ],
                                                    })
                                                }
                                            >
                                                {account.name}
                                            </button>
                                        ) : (
                                            'Cuenta eliminada'
                                        )}
                                    </div>
                                    <AccountBalanceLine
                                        balance={sourceBalance}
                                        currency={
                                            account?.currency ??
                                            transaction.currency
                                        }
                                    />
                                </div>
                            )}
                        </ReceiptRow>

                        {isTransfer ? (
                            <ReceiptRow
                                icon={<WalletCards />}
                                label="Cuenta destino"
                                stacked
                            >
                                {editing ? (
                                    <AccountSelect
                                        value={toAccountId}
                                        accounts={accounts}
                                        excludedId={accountId}
                                        onChange={setToAccountId}
                                    />
                                ) : (
                                    <div className="space-y-1">
                                        <div>
                                            {destinationAccount ? (
                                                <button
                                                    type="button"
                                                    className="cursor-pointer"
                                                    onClick={() =>
                                                        applyFilter({
                                                            accountIds: [
                                                                destinationAccount.id,
                                                            ],
                                                        })
                                                    }
                                                >
                                                    {destinationAccount.name}
                                                </button>
                                            ) : (
                                                'Cuenta eliminada'
                                            )}
                                        </div>
                                        <AccountBalanceLine
                                            balance={destBalance}
                                            currency={
                                                destinationAccount?.currency ??
                                                transaction.toCurrency ??
                                                transaction.currency
                                            }
                                        />
                                    </div>
                                )}
                            </ReceiptRow>
                        ) : null}

                        {transaction.type !== 'balance_adjustment' ? (
                            <ReceiptRow
                                icon={
                                    <CategoryIcon
                                        name={category?.icon}
                                        className="size-4"
                                        color={categoryColor}
                                    />
                                }
                                label="Categoría"
                            >
                                {editing ? (
                                    <select
                                        value={categoryId}
                                        onChange={(event) =>
                                            setCategoryId(event.target.value)
                                        }
                                        className="h-9 max-w-52 rounded-md border bg-transparent px-3 text-sm"
                                        required
                                    >
                                        {categories.map((item) => (
                                            <option
                                                key={item.id}
                                                value={item.id}
                                            >
                                                {item.name}
                                            </option>
                                        ))}
                                    </select>
                                ) : category ? (
                                    <button
                                        type="button"
                                        className="cursor-pointer"
                                        onClick={() =>
                                            applyFilter({
                                                categoryIds: [category.id],
                                            })
                                        }
                                    >
                                        {category.name}
                                    </button>
                                ) : null}
                            </ReceiptRow>
                        ) : null}

                        <ReceiptRow icon={<Tags />} label="Tags" stacked>
                            {editing || hasSelectedTags ? (
                                <div className="flex flex-wrap gap-2">
                                    {tags.length === 0 ? (
                                        <span className="text-muted-foreground">
                                            Sin tags
                                        </span>
                                    ) : (
                                        tags.map((tag) => {
                                            const selected = selectedTagIds.has(
                                                tag.id,
                                            )
                                            if (!editing && !selected)
                                                return null
                                            return (
                                                <button
                                                    key={tag.id}
                                                    type="button"
                                                    onClick={
                                                        editing
                                                            ? () =>
                                                                  setSelectedTagIds(
                                                                      (
                                                                          current,
                                                                      ) => {
                                                                          const next =
                                                                              new Set(
                                                                                  current,
                                                                              )
                                                                          if (
                                                                              next.has(
                                                                                  tag.id,
                                                                              )
                                                                          )
                                                                              next.delete(
                                                                                  tag.id,
                                                                              )
                                                                          else
                                                                              next.add(
                                                                                  tag.id,
                                                                              )
                                                                          return next
                                                                      },
                                                                  )
                                                            : () =>
                                                                  applyFilter({
                                                                      tagIds: [
                                                                          tag.id,
                                                                      ],
                                                                  })
                                                    }
                                                >
                                                    <Badge
                                                        variant={
                                                            selected
                                                                ? 'secondary'
                                                                : 'outline'
                                                        }
                                                        className={cn(
                                                            'rounded-full cursor-pointer',
                                                            !selected &&
                                                                'opacity-50',
                                                        )}
                                                        style={
                                                            selected
                                                                ? {
                                                                      backgroundColor:
                                                                          normalizeTagColor(
                                                                              tag.color,
                                                                          ),
                                                                      color: '#111',
                                                                  }
                                                                : undefined
                                                        }
                                                    >
                                                        {tag.name}
                                                    </Badge>
                                                </button>
                                            )
                                        })
                                    )}
                                </div>
                            ) : null}
                        </ReceiptRow>
                    </div>
                </div>
            </form>

            {editing ? (
                <SheetFooter className="border-t bg-background">
                    <Button
                        type="submit"
                        form={formId}
                        disabled={saving}
                        className="w-full"
                    >
                        <Check />
                        {saving ? 'Guardando…' : 'Guardar cambios'}
                    </Button>
                </SheetFooter>
            ) : null}

            <Dialog open={deleteOpen} onOpenChange={setDeleteOpen}>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Eliminar actividad</DialogTitle>
                    </DialogHeader>
                    <p className="text-sm text-muted-foreground">
                        ¿Seguro que querés eliminar “{transaction.name}”?
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
                            onClick={() => void handleDelete()}
                            disabled={saving}
                        >
                            Eliminar
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </>
    )
}

function ReceiptRow({
    icon,
    label,
    attention = false,
    stacked = false,
    children,
}: {
    icon: ReactNode
    label: string
    attention?: boolean
    stacked?: boolean
    children: ReactNode
}) {
    const heading = (
        <div
            className={cn(
                'flex items-center gap-2 text-sm font-medium [&_svg]:size-4',
                attention
                    ? 'text-orange-700 dark:text-orange-500'
                    : 'text-muted-foreground',
            )}
        >
            {icon}
            <span>{label}</span>
        </div>
    )

    return stacked ? (
        <div className="space-y-2 py-4">
            {heading}
            {children != null ? (
                <div className="font-medium">{children}</div>
            ) : null}
        </div>
    ) : (
        <div className="flex items-center justify-between gap-4 py-4">
            {heading}
            {children != null ? (
                <div className="text-right font-medium">{children}</div>
            ) : null}
        </div>
    )
}

// Reads as a muted "… → …" balance line under the account name, with a
// skeleton while loading and a fallback when the balance can't be resolved.
function AccountBalanceLine({
    balance,
    currency,
}: {
    balance: AccountBalance | undefined
    currency: string
}) {
    if (balance === undefined) {
        return <Skeleton className="h-4 w-40" />
    }
    if (balance === null) {
        return (
            <span className="text-sm font-normal text-muted-foreground">
                Saldo no disponible
            </span>
        )
    }
    return (
        <span className="text-sm font-normal text-muted-foreground tabular-nums">
            {formatMoney(Number(balance.before), currency)} →{' '}
            {formatMoney(Number(balance.after), currency)}
        </span>
    )
}

function AccountSelect({
    value,
    accounts,
    excludedId,
    onChange,
}: {
    value: string
    accounts: Account[]
    excludedId?: string
    onChange: (value: string) => void
}) {
    return (
        <select
            value={value}
            onChange={(event) => onChange(event.target.value)}
            className="h-9 w-full rounded-md border bg-transparent px-3 text-sm"
            required
        >
            {accounts
                .filter(
                    (account) =>
                        account.id === value ||
                        (!account.isArchived && account.id !== excludedId),
                )
                .map((account) => (
                    <option key={account.id} value={account.id}>
                        {account.name} · {account.currency}
                    </option>
                ))}
        </select>
    )
}

function TransactionDetailsSkeleton() {
    return (
        <div className="space-y-4 p-4">
            <Skeleton className="h-8 w-40" />
            <Skeleton className="h-48 rounded-2xl" />
            <Skeleton className="h-64 rounded-2xl" />
        </div>
    )
}

function displayAmount(
    transaction: Transaction,
    side?: TransactionTransferSide,
): bigint {
    return side === 'destination'
        ? (transaction.toAmount ?? transaction.amount)
        : transaction.amount
}

function displaySignedAmount(
    transaction: Transaction,
    side?: TransactionTransferSide,
): number {
    const amount = Number(displayAmount(transaction, side))
    switch (transaction.type) {
        case 'expense':
            return -Math.abs(amount)
        case 'income':
            return Math.abs(amount)
        case 'transfer':
            return side === 'source' ? -Math.abs(amount) : Math.abs(amount)
        case 'balance_adjustment':
            return amount
    }
}

function centsToInput(cents: bigint): string {
    return (Number(cents < 0n ? -cents : cents) / 100).toFixed(2)
}

function normalizeAmount(value: string): string {
    const normalized = value.replace(',', '.')
    return normalized.replace(/[^\d.]/g, '').replace(/(\..*)\./g, '$1')
}

function inputToCents(value: string): bigint | null {
    const parsed = Number(value.replace(',', '.'))
    if (!Number.isFinite(parsed)) return null
    return BigInt(Math.round(Math.abs(parsed) * 100))
}

function dateInputValue(epoch: bigint): string {
    const date = new Date(Number(epoch))
    return `${date.getFullYear().toString().padStart(4, '0')}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`
}

function timeInputValue(epoch: bigint): string {
    const date = new Date(Number(epoch))
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`
}

function localDateTimeEpoch(dateValue: string, timeValue: string): bigint {
    const [year, month, day] = dateValue.split('-').map(Number)
    const [hour, minute] = timeValue.split(':').map(Number)
    return BigInt(new Date(year, month - 1, day, hour, minute, 0, 0).getTime())
}

function formatDate(epoch: bigint): string {
    return new Intl.DateTimeFormat('es-AR').format(new Date(Number(epoch)))
}

function formatTime(epoch: bigint): string {
    return new Intl.DateTimeFormat('es-AR', {
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
    }).format(new Date(Number(epoch)))
}
