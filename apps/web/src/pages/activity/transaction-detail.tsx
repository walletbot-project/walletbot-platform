import { api } from '@wallet-bot/backend/api'
import { CircularProgress, IconButton, Select, SelectOption } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import type { FunctionReturnType } from 'convex/server'
import { type ReactNode, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { AccountIcon } from '@/components/account-icon'
import { CategoryIcon } from '@/components/category-icon'
import { AppBar } from '@/components/m3/app-bar'
import { DateField } from '@/components/m3/date-field'
import { DialogAction, M3Dialog } from '@/components/m3/dialog'
import { Icon } from '@/components/m3/icon'
import { TimeField } from '@/components/m3/time-field'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { Textarea } from '@/components/ui/textarea'
import {
    ACCOUNT_DEFAULT_COLOR,
    CATEGORY_DEFAULT_COLOR,
    normalizeColor,
} from '@/lib/entity-colors'
import { useFormatLocale, useT } from '@/lib/i18n'
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

type TransactionDetailProps = {
    transactionId: string
    transferSide?: TransactionTransferSide
    initialEditing?: boolean
    // When provided, the read-mode date/category/tag chips apply the filter in
    // place (used by the Activity page, which owns the filter state). Without
    // it, they deep-link to /activity via the router.
    onApplyFilter?: (filters: Partial<TransactionFilters>) => void
    onClose: () => void
}

/**
 * A transaction's details, with an inline edit mode. It is a PAGE below the
 * split and the right pane above it — never a sheet — because the native
 * Activity screen presents it as a real `MaterialPageRoute` (activity.dart:49).
 * Its route therefore carries `handle: { fullScreen: true }`, and it heads
 * itself with the standard `AppBar` at every width.
 */
export function TransactionDetail({
    transactionId,
    transferSide,
    initialEditing = false,
    onApplyFilter,
    onClose,
}: TransactionDetailProps) {
    const t = useT()
    const transaction = useQuery(api.v1.transactions.queries.get, {
        id: transactionId,
    })
    const accounts = useQuery(api.v1.accounts.queries.list, {
        includeArchived: true,
    })
    const categories = useQuery(api.v1.categories.queries.listActive)
    const currentCategory = useQuery(
        api.v1.categories.queries.get,
        transaction?.categoryId ? { id: transaction.categoryId } : 'skip',
    )
    const tags = useQuery(api.v1.tags.queries.listActive)

    const isLoading =
        transaction === undefined ||
        accounts === undefined ||
        categories === undefined ||
        (transaction !== null &&
            transaction.categoryId !== '' &&
            currentCategory === undefined) ||
        tags === undefined

    const categoryOptions =
        categories &&
        currentCategory &&
        !categories.some((category) => category.id === currentCategory.id)
            ? [...categories, currentCategory]
            : categories

    if (isLoading) return <TransactionDetailsSkeleton />
    if (transaction === null) {
        return (
            <div className="m3-body-large flex flex-1 items-center justify-center p-8 text-on-surface-variant">
                {t.transaction.gone}
            </div>
        )
    }
    return (
        <TransactionDetailsContent
            key={`${transaction.id}-${transaction.updatedAt}`}
            transaction={transaction}
            accounts={accounts}
            categories={categoryOptions ?? categories}
            tags={tags}
            transferSide={transferSide}
            initialEditing={initialEditing}
            onApplyFilter={onApplyFilter}
            onClose={onClose}
        />
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
    const t = useT()
    const formatLocale = useFormatLocale()

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

    const handleSave = async () => {
        const trimmedName = name.trim()
        if (!trimmedName) {
            toast.error(t.common.nameCannotBeEmpty)
            return
        }
        if (!account) {
            toast.error(t.transaction.chooseAccount)
            return
        }
        if (isTransfer && (!destinationAccount || accountId === toAccountId)) {
            toast.error(t.transaction.sameAccounts)
            return
        }

        let parsedAmount: bigint | undefined
        if (canEditAmount) {
            const parsed = inputToCents(amount)
            if (parsed === null || parsed <= 0n) {
                toast.error(t.transaction.amountGreaterThanZero)
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
                // Tags ride in the same mutation so the edit and its tag
                // changes commit atomically (no partially-saved state).
                addTagIds: toAdd.length > 0 ? toAdd : undefined,
                removeTagIds: toRemove.length > 0 ? toRemove : undefined,
            })
            toast.success(t.transaction.updated)
            setEditing(false)
        } catch (error) {
            toast.error(
                error instanceof Error
                    ? error.message
                    : t.transaction.updateFailed,
            )
        } finally {
            setSaving(false)
        }
    }

    const handleDelete = async () => {
        setSaving(true)
        try {
            await archiveTransaction({ id: transaction.id })
            toast.success(t.transaction.deleted)
            setDeleteOpen(false)
            onClose()
        } catch {
            toast.error(t.transaction.deleteFailed)
        } finally {
            setSaving(false)
        }
    }

    return (
        <>
            {/*
             * The standard top app bar, identical to every other one in the
             * app. This screen is a page at every width (the native Activity
             * pushes it as a real route), so unlike `DetailPaneHeader` the bar
             * is never hidden — but it is the same `AppBar`, with the same
             * height and leading inset, and no border: Material 3 app bars
             * separate themselves with a surface tint on scroll, and no app bar
             * in the native app carries a rule.
             */}
            <AppBar
                title={
                    editing ? t.transaction.editActivity : t.transaction.detail
                }
                leading={
                    <IconButton
                        aria-label={t.common.close}
                        onPress={onClose}
                        isDisabled={saving}
                        className="text-on-surface-variant"
                    >
                        <Icon name="close" />
                    </IconButton>
                }
                actions={
                    <>
                        {/*
                         * One action toggles between reading and editing, as in
                         * native's `_toggleEditing`
                         * (`transaction_details_sheet.dart:601`): a pencil while
                         * reading, a check that commits while editing, and a
                         * spinner in its place while the save is in flight.
                         */}
                        {saving ? (
                            <span
                                className="flex size-10 shrink-0 items-center justify-center"
                                aria-hidden
                            >
                                <CircularProgress isIndeterminate size="xs" />
                            </span>
                        ) : (
                            <IconButton
                                aria-label={
                                    editing ? t.common.save : t.common.edit
                                }
                                onPress={() =>
                                    editing
                                        ? void handleSave()
                                        : setEditing(true)
                                }
                                className="text-on-surface-variant"
                            >
                                <Icon name={editing ? 'check' : 'edit'} />
                            </IconButton>
                        )}
                        <IconButton
                            aria-label={t.common.delete}
                            onPress={() => setDeleteOpen(true)}
                            isDisabled={saving}
                            className="text-on-surface-variant"
                        >
                            <Icon name="delete" />
                        </IconButton>
                    </>
                }
            />

            <form
                onSubmit={(event) => {
                    event.preventDefault()
                    void handleSave()
                }}
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
                                size={32}
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
                                aria-label={t.common.name}
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
                                aria-label={t.transaction.amount}
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
                                {formatMoney(
                                    signedAmount,
                                    displayCurrency,
                                    formatLocale,
                                )}
                            </p>
                        )}
                    </div>

                    <div className="mx-6 border-t border-dashed" />

                    <div className="divide-y px-6">
                        <ReceiptRow
                            icon={<Icon name="description" filled />}
                            label={t.common.description}
                            stacked
                        >
                            {editing ? (
                                <Textarea
                                    value={description}
                                    onChange={(event) =>
                                        setDescription(event.target.value)
                                    }
                                    rows={3}
                                    placeholder={t.transaction.noDescription}
                                />
                            ) : transaction.description ? (
                                <span>{transaction.description}</span>
                            ) : null}
                        </ReceiptRow>

                        <ReceiptRow
                            icon={
                                dateConfirmed ? (
                                    <Icon name="calendar_month" filled />
                                ) : (
                                    <Icon name="help" />
                                )
                            }
                            label={
                                dateConfirmed
                                    ? t.transaction.date
                                    : t.transaction.estimatedDate
                            }
                            attention={!dateConfirmed}
                        >
                            {editing ? (
                                <DateField
                                    value={date}
                                    onChange={(next) => {
                                        setDate(next)
                                        setDateConfirmed(true)
                                        setDateTouched(true)
                                    }}
                                    label={t.transaction.date}
                                    compact
                                    className="w-auto"
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
                                    {formatDate(transaction.date, formatLocale)}
                                </button>
                            )}
                        </ReceiptRow>

                        <ReceiptRow
                            icon={
                                timeNeedsAttention ? (
                                    <Icon name="help" />
                                ) : (
                                    <Icon name="schedule" />
                                )
                            }
                            label={
                                timeNeedsAttention
                                    ? t.transaction.estimatedTime
                                    : t.transaction.time
                            }
                            attention={timeNeedsAttention}
                        >
                            {editing ? (
                                <TimeField
                                    value={time}
                                    onChange={(next) => {
                                        setTime(next)
                                        setTimeStatus('confirmed')
                                        setTimeTouched(true)
                                    }}
                                    label={t.transaction.time}
                                    compact
                                />
                            ) : (
                                formatTime(transaction.date, formatLocale)
                            )}
                        </ReceiptRow>

                        <ReceiptRow
                            icon={
                                <AccountIcon
                                    name={account?.icon}
                                    size={16}
                                    color={normalizeColor(
                                        account?.color,
                                        ACCOUNT_DEFAULT_COLOR,
                                    )}
                                />
                            }
                            label={
                                isTransfer
                                    ? t.transaction.sourceAccount
                                    : t.transaction.account
                            }
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
                                    label={
                                        isTransfer
                                            ? t.transaction.sourceAccount
                                            : t.transaction.account
                                    }
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
                                            t.transaction.deletedAccount
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
                                icon={
                                    <Icon
                                        name="account_balance_wallet"
                                        filled
                                    />
                                }
                                label={t.transaction.destinationAccount}
                                stacked
                            >
                                {editing ? (
                                    <AccountSelect
                                        value={toAccountId}
                                        accounts={accounts}
                                        excludedId={accountId}
                                        onChange={setToAccountId}
                                        label={t.transaction.destinationAccount}
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
                                                t.transaction.deletedAccount
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
                                        size={16}
                                        color={categoryColor}
                                    />
                                }
                                label={t.transaction.category}
                            >
                                {editing ? (
                                    <Select
                                        aria-label={t.transaction.category}
                                        variant="outlined"
                                        className="max-w-52"
                                        selectedKey={categoryId}
                                        onSelectionChange={(key) =>
                                            setCategoryId(String(key))
                                        }
                                    >
                                        {categories.map((item) => (
                                            <SelectOption key={item.id}>
                                                {item.name}
                                            </SelectOption>
                                        ))}
                                    </Select>
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

                        <ReceiptRow
                            icon={<Icon name="sell" filled />}
                            label={t.transaction.tags}
                            stacked
                        >
                            {editing || hasSelectedTags ? (
                                <div className="flex flex-wrap gap-2">
                                    {tags.length === 0 ? (
                                        <span className="text-muted-foreground">
                                            {t.transaction.noTags}
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

            <M3Dialog
                open={deleteOpen}
                onOpenChange={setDeleteOpen}
                title={t.transaction.deleteTitle}
                description={t.transaction.deleteConfirm({
                    name: transaction.name,
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
                            onPress={() => void handleDelete()}
                            isDisabled={saving}
                            destructive
                        />
                    </>
                }
            />
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
    const t = useT()
    const formatLocale = useFormatLocale()
    if (balance === undefined) {
        return <Skeleton className="h-4 w-40" />
    }
    if (balance === null) {
        return (
            <span className="text-sm font-normal text-muted-foreground">
                {t.transaction.balanceUnavailable}
            </span>
        )
    }
    return (
        <span className="text-sm font-normal text-muted-foreground tabular-nums">
            {formatMoney(Number(balance.before), currency, formatLocale)} →{' '}
            {formatMoney(Number(balance.after), currency, formatLocale)}
        </span>
    )
}

function AccountSelect({
    value,
    accounts,
    excludedId,
    onChange,
    label,
}: {
    value: string
    accounts: Account[]
    excludedId?: string
    onChange: (value: string) => void
    label: string
}) {
    return (
        <Select
            aria-label={label}
            variant="outlined"
            className="w-full"
            selectedKey={value}
            onSelectionChange={(key) => onChange(String(key))}
        >
            {accounts
                .filter(
                    (account) =>
                        account.id === value ||
                        (!account.isArchived && account.id !== excludedId),
                )
                .map((account) => (
                    <SelectOption key={account.id}>
                        {`${account.name} · ${account.currency}`}
                    </SelectOption>
                ))}
        </Select>
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
            // An omitted side defaults to the source (outgoing) leg — the sheet
            // opens on the source account when no side is passed.
            return side === 'destination' ? Math.abs(amount) : -Math.abs(amount)
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

function formatDate(epoch: bigint, locale: string): string {
    return new Intl.DateTimeFormat(locale).format(new Date(Number(epoch)))
}

function formatTime(epoch: bigint, locale: string): string {
    return new Intl.DateTimeFormat(locale, {
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
    }).format(new Date(Number(epoch)))
}
