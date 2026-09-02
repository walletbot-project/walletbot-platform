import { api } from '@wallet-bot/backend/api'
import type { RecurrenceSpan } from '@wallet-bot/shared'
import {
    computeExchangeRate,
    parseAmountToCents,
    parseTransactionDate,
    recurrenceHorizon,
} from '@wallet-bot/shared'
import {
    Button,
    CircularProgress,
    IconButton,
    SegmentedButton,
    SegmentedButtonSet,
    Switch,
    TextField,
} from 'actify'
import { useMutation, useQuery } from 'convex/react'
import {
    type FormEvent,
    type ReactNode,
    useEffect,
    useMemo,
    useState,
} from 'react'
import { toast } from 'sonner'
import { ColorSwatches } from '@/components/color-swatches'
import { ChoiceChip } from '@/components/m3/chip'
import { DateField } from '@/components/m3/date-field'
import { DialogAction, M3Dialog } from '@/components/m3/dialog'
import { FormScreen } from '@/components/m3/form-screen'
import { Icon } from '@/components/m3/icon'
import { OptionSheet, type SheetOption } from '@/components/m3/option-sheet'
import { PickerField } from '@/components/m3/picker-field'
import { TagChip } from '@/components/m3/tag-chip'
import { TimeField } from '@/components/m3/time-field'
import {
    CURRENCY_CODES,
    currencyName,
    DEFAULT_CURRENCY,
    SUGGESTED_CURRENCIES,
} from '@/lib/currencies'
import { type Messages, useFormatLocale, useT } from '@/lib/i18n'
import { newId } from '@/lib/new-id'
import { TAG_COLOR_OPTIONS } from '@/lib/tag-colors'

type MovementType = 'income' | 'expense' | 'transfer'

type RecurrenceFrequency =
    | 'daily'
    | 'weekly'
    | 'monthly'
    | 'yearly'
    | 'customDays'

const DEFAULT_RECURRENCE_DAY_INTERVAL = 15

const RECURRENCE_FREQUENCIES: readonly RecurrenceFrequency[] = [
    'daily',
    'weekly',
    'monthly',
    'yearly',
    'customDays',
]

function recurrenceFrequencyLabel(
    frequency: RecurrenceFrequency,
    t: Messages,
): string {
    switch (frequency) {
        case 'daily':
            return t.addManual.recurrenceDaily
        case 'weekly':
            return t.addManual.recurrenceWeekly
        case 'monthly':
            return t.addManual.recurrenceMonthly
        case 'yearly':
            return t.addManual.recurrenceYearly
        case 'customDays':
            return t.addManual.recurrenceCustomDays
    }
}

type AccountOption = {
    id: string
    name: string
    currency: string
}

type CategoryOption = {
    id: string
    name: string
}

type FormTag = {
    id?: string
    name: string
    color: string
}

const MOVEMENT_TYPES: readonly MovementType[] = [
    'income',
    'expense',
    'transfer',
]

/**
 * Accent per movement type. These sit outside the seeded color scheme on
 * purpose — they are the same three literals the native transaction form uses
 * for its type segmented button (apps/native/lib/screens/transaction_form.dart).
 */
const SELECTED_COLORS: Record<
    MovementType,
    { background: string; foreground: string }
> = {
    income: { background: '#00E676', foreground: '#000000' },
    expense: { background: '#FF3744', foreground: '#FFFFFF' },
    transfer: { background: '#6DE7D8', foreground: '#000000' },
}

function typeCopy(type: MovementType, t: Messages) {
    switch (type) {
        case 'income':
            return {
                label: t.addManual.incomeLabel,
                title: t.addManual.incomeTitle,
                description: t.addManual.incomeDescription,
                amountLabel: t.addManual.amount,
            }
        case 'expense':
            return {
                label: t.addManual.expenseLabel,
                title: t.addManual.expenseTitle,
                description: t.addManual.expenseDescription,
                amountLabel: t.addManual.amount,
            }
        case 'transfer':
            return {
                label: t.addManual.transferLabel,
                title: t.addManual.transferTitle,
                description: t.addManual.transferDescription,
                amountLabel: t.addManual.outgoing,
            }
    }
}

function today() {
    const date = new Date()
    return `${date.getFullYear().toString().padStart(4, '0')}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`
}

function defaultDestinationAccountId(
    sourceId: string,
    accounts: AccountOption[],
): string {
    if (!sourceId) return ''
    return accounts.find((account) => account.id !== sourceId)?.id ?? ''
}

function normalizeAmountInput(value: string) {
    let hasSeparator = false

    return Array.from(value)
        .filter((char) => {
            if (/\d/.test(char)) return true
            if ((char === ',' || char === '.') && !hasSeparator) {
                hasSeparator = true
                return true
            }
            return false
        })
        .join('')
}

function parseFormAmount(value: string): number | null {
    const parsed = Number(value.trim().replace(',', '.'))
    if (!Number.isFinite(parsed) || parsed <= 0) return null
    return parsed
}

function normalizeIdentity(value: string) {
    return value.trim().toLowerCase()
}

function mergeAccounts(
    base: AccountOption[],
    extra: AccountOption[],
): AccountOption[] {
    return Array.from(
        new Map(
            [...base, ...extra].map((account) => [account.id, account]),
        ).values(),
    )
}

function mergeCategories(
    base: CategoryOption[],
    extra: CategoryOption[],
): CategoryOption[] {
    return Array.from(
        new Map(
            [...base, ...extra].map((category) => [category.id, category]),
        ).values(),
    )
}

function mergeTags(base: FormTag[], extra: FormTag[]): FormTag[] {
    return Array.from(
        new Map(
            [...base, ...extra].map((tag) => [
                tag.id ?? normalizeIdentity(tag.name),
                tag,
            ]),
        ).values(),
    )
}

/**
 * The manual transaction form, ported from `TransactionFormScreen`. It never
 * navigates on its own: the host decides where it lives (the divided view's
 * pane on expanded windows, over the window below that) and what closing and
 * saving mean, exactly like the native form's `onResult` contract.
 */
export function TransactionForm({
    onClose,
    onSaved,
}: {
    onClose: () => void
    onSaved: () => void
}) {
    const t = useT()

    const accounts = useQuery(api.v1.accounts.queries.listActive)
    const categories = useQuery(api.v1.categories.queries.listActive)
    const availableTags = useQuery(api.v1.tags.queries.listActive)
    const settings = useQuery(api.v1.users.queries.getSettings, {})
    const flags = useQuery(api.v1.featureFlags.queries.getMyFlags)

    const createIncome = useMutation(api.v1.transactions.mutations.createIncome)
    const createRecurrence = useMutation(api.v1.recurrences.mutations.create)
    const createExpense = useMutation(
        api.v1.transactions.mutations.createExpense,
    )
    const createTransfer = useMutation(
        api.v1.transactions.mutations.createTransfer,
    )
    const createAccount = useMutation(api.v1.accounts.mutations.create)
    const createCategory = useMutation(api.v1.categories.mutations.create)
    const tagTransaction = useMutation(api.v1.transactions.mutations.tag)
    const createTag = useMutation(api.v1.tags.mutations.create)

    const [createdAccounts, setCreatedAccounts] = useState<AccountOption[]>([])
    const [createdCategories, setCreatedCategories] = useState<
        CategoryOption[]
    >([])
    const [createdTags, setCreatedTags] = useState<FormTag[]>([])
    const [isCreateAccountOpen, setIsCreateAccountOpen] = useState(false)
    const [isCreateCategoryOpen, setIsCreateCategoryOpen] = useState(false)

    const accountOptions = mergeAccounts(
        (accounts ?? []).map((account) => ({
            id: account.id,
            name: account.name,
            currency: account.currency,
        })),
        createdAccounts,
    )
    const categoryOptions = mergeCategories(
        (categories ?? []).map((category) => ({
            id: category.id,
            name: category.name,
        })),
        createdCategories,
    )
    const knownTags = mergeTags(
        [
            ...(availableTags ?? []).map((tag) => ({
                id: tag.id,
                name: tag.name,
                color: tag.color ?? TAG_COLOR_OPTIONS[0],
            })),
        ],
        createdTags,
    )

    const [type, setType] = useState<MovementType>('income')
    const [amount, setAmount] = useState('0')
    const [destinationAmount, setDestinationAmount] = useState('0')
    const [sourceAmountTouched, setSourceAmountTouched] = useState(false)
    const [destinationAmountTouched, setDestinationAmountTouched] =
        useState(false)
    const [title, setTitle] = useState('')
    const [description, setDescription] = useState('')
    const [date, setDate] = useState(today)
    const [time, setTime] = useState('')
    const [accountId, setAccountId] = useState('')
    const [destinationAccountId, setDestinationAccountId] = useState('')
    const [categoryId, setCategoryId] = useState('')
    const [tagInput, setTagInput] = useState('')
    const [tags, setTags] = useState<FormTag[]>([])
    const [pendingTagName, setPendingTagName] = useState<string | null>(null)
    const [pendingTagColor, setPendingTagColor] = useState<string>(
        TAG_COLOR_OPTIONS[0],
    )
    // Display-only, exactly as on native: the recurring-expense feature isn't
    // built yet, so the toggle is never read on save and never persisted
    // (`_isRecurring` in apps/native/lib/screens/transaction_form.dart).
    const [isSaving, setIsSaving] = useState(false)
    const [isRecurring, setIsRecurring] = useState(false)
    const [recurrenceFrequency, setRecurrenceFrequency] =
        useState<RecurrenceFrequency>('monthly')
    const [recurrenceDayInterval, setRecurrenceDayInterval] = useState(
        DEFAULT_RECURRENCE_DAY_INTERVAL,
    )
    const [recurrenceEndDate, setRecurrenceEndDate] = useState('')

    // Same gate as native's transaction form: behind the `recurringExpense`
    // flag, and off for transfers (`_type != TransactionFormType.transfer`).
    const showRecurrence =
        type !== 'transfer' && flags?.recurringExpense === true

    useEffect(() => {
        setAccountId((current) => {
            if (
                current &&
                accountOptions.some((account) => account.id === current)
            ) {
                return current
            }
            return ''
        })
    }, [accountOptions])

    useEffect(() => {
        setDestinationAccountId((current) => {
            const fallback = defaultDestinationAccountId(
                accountId,
                accountOptions,
            )
            if (
                current &&
                current !== accountId &&
                accountOptions.some((account) => account.id === current)
            ) {
                return current
            }
            return fallback
        })
    }, [accountId, accountOptions])

    useEffect(() => {
        setCategoryId((current) => {
            if (
                current &&
                categoryOptions.some((category) => category.id === current)
            ) {
                return current
            }
            return ''
        })
    }, [categoryOptions])

    const selectedAccount = accountOptions.find(
        (account) => account.id === accountId,
    )
    const selectedCategory = categoryOptions.find(
        (category) => category.id === categoryId,
    )
    const config = typeCopy(type, t)

    const resetFields = () => {
        setAmount('0')
        setDestinationAmount('0')
        setSourceAmountTouched(false)
        setDestinationAmountTouched(false)
        setTitle('')
        setDescription('')
        setDate(today())
        setTime('')
        setAccountId('')
        setDestinationAccountId('')
        setCategoryId('')
        setTagInput('')
        setTags([])
        setPendingTagName(null)
        setPendingTagColor(TAG_COLOR_OPTIONS[0])
        setIsRecurring(false)
        setRecurrenceFrequency('monthly')
        setRecurrenceDayInterval(DEFAULT_RECURRENCE_DAY_INTERVAL)
        setRecurrenceEndDate('')
    }

    const changeType = (nextType: MovementType) => {
        setType(nextType)
        resetFields()
    }

    const addResolvedTag = (tag: FormTag) => {
        setTags((current) =>
            current.some(
                (item) => item.name.toLowerCase() === tag.name.toLowerCase(),
            )
                ? current
                : [...current, tag],
        )
    }

    const addTag = (raw: string) => {
        const name = raw.trim()
        if (!name) return
        const existing = knownTags.find(
            (tag) => tag.name.toLowerCase() === name.toLowerCase(),
        )
        if (!existing) {
            setPendingTagName(name)
            setPendingTagColor(TAG_COLOR_OPTIONS[0])
            return
        }

        addResolvedTag(existing)
        setTagInput('')
    }

    const createPendingTag = async () => {
        if (!pendingTagName) return
        const existing = knownTags.find(
            (tag) => tag.name.toLowerCase() === pendingTagName.toLowerCase(),
        )
        if (existing) {
            addResolvedTag(existing)
            setTagInput('')
            setPendingTagName(null)
            return
        }
        const createdTag = {
            id: newId(),
            name: pendingTagName,
            color: pendingTagColor,
        }
        try {
            await createTag({
                id: createdTag.id,
                name: createdTag.name,
                color: createdTag.color,
            })
        } catch {
            // Uncaught, this was an unhandled rejection: the color dialog hung
            // open with no feedback.
            toast.error(t.common.saveFailed)
            return
        }
        setCreatedTags((current) => [...current, createdTag])
        addResolvedTag(createdTag)
        setTagInput('')
        setPendingTagName(null)
    }

    const sameTransferCurrency = () => {
        const source = accountOptions.find(
            (account) => account.id === accountId,
        )
        const destination = accountOptions.find(
            (account) => account.id === destinationAccountId,
        )
        return (
            type === 'transfer' &&
            source !== undefined &&
            destination !== undefined &&
            source.currency === destination.currency
        )
    }

    const updateSourceAmount = (value: string) => {
        const normalizedValue = normalizeAmountInput(value)
        setAmount(normalizedValue)
        setSourceAmountTouched(true)
        if (sameTransferCurrency() && !destinationAmountTouched) {
            setDestinationAmount(normalizedValue)
        }
    }

    const updateDestinationAmount = (value: string) => {
        const normalizedValue = normalizeAmountInput(value)
        setDestinationAmount(normalizedValue)
        setDestinationAmountTouched(true)
        if (sameTransferCurrency() && !sourceAmountTouched) {
            setAmount(normalizedValue)
        }
    }

    const updateSourceAccount = (value: string) => {
        setAccountId(value)
        const source = accountOptions.find((account) => account.id === value)
        const destination = accountOptions.find(
            (account) => account.id === destinationAccountId,
        )
        if (
            type === 'transfer' &&
            source?.currency === destination?.currency &&
            amount &&
            !destinationAmountTouched
        ) {
            setDestinationAmount(amount)
        }
    }

    const updateDestinationAccount = (value: string) => {
        setDestinationAccountId(value)
        const source = accountOptions.find(
            (account) => account.id === accountId,
        )
        const destination = accountOptions.find(
            (account) => account.id === value,
        )
        if (
            type === 'transfer' &&
            source?.currency === destination?.currency &&
            destinationAmount &&
            !sourceAmountTouched
        ) {
            setAmount(destinationAmount)
        } else if (
            type === 'transfer' &&
            source?.currency === destination?.currency &&
            amount &&
            !destinationAmountTouched
        ) {
            setDestinationAmount(amount)
        }
    }

    const swapTransferSides = () => {
        const currentSourceAccountId = accountId
        const currentSourceAmount = amount
        const currentSourceTouched = sourceAmountTouched

        setAccountId(destinationAccountId)
        setDestinationAccountId(currentSourceAccountId)
        setAmount(destinationAmount)
        setDestinationAmount(currentSourceAmount)
        setSourceAmountTouched(destinationAmountTouched)
        setDestinationAmountTouched(currentSourceTouched)
    }

    const ensureTag = async (tag: FormTag): Promise<string> => {
        if (tag.id) return tag.id

        const existing = knownTags.find(
            (candidate) =>
                candidate.name.toLowerCase() === tag.name.toLowerCase(),
        )
        if (existing?.id) return existing.id

        const id = newId()
        await createTag({
            id,
            name: tag.name,
            color: tag.color,
        })
        return id
    }

    const submit = async (event: FormEvent<HTMLFormElement>) => {
        event.preventDefault()
        if (!selectedAccount) {
            toast.error(t.addManual.selectAccount)
            return
        }
        if (!selectedCategory) {
            toast.error(t.addManual.selectCategory)
            return
        }
        const parsedAmount = parseFormAmount(amount)
        if (!parsedAmount) {
            toast.error(t.addManual.amountGreaterThanZero)
            return
        }

        const trimmedTitle =
            type === 'transfer'
                ? t.addManual.transferTitleFallback
                : title.trim()
        if (!trimmedTitle) {
            toast.error(t.addManual.titleRequired)
            return
        }

        const timeStatus = time ? 'confirmed' : 'none'
        const sourceDate = parseTransactionDate(
            date,
            timeStatus,
            time || undefined,
        )
        const trimmedDescription = description.trim() || undefined

        if (type === 'transfer') {
            if (!destinationAccountId) {
                toast.error(t.addManual.selectDestinationAccount)
                return
            }
            if (destinationAccountId === accountId) {
                toast.error(t.addManual.distinctAccounts)
                return
            }
        }

        setIsSaving(true)
        try {
            const resolvedTagIds: string[] = []
            for (const tag of tags) {
                resolvedTagIds.push(await ensureTag(tag))
            }

            const transactionId = newId()
            if (showRecurrence && isRecurring) {
                // One call creates the rule and this movement as occurrence 0;
                // the rest of the series is materialised by a workflow, so the
                // form returns as soon as the first one exists.
                await createRecurrence({
                    recurrenceId: newId(),
                    frequency: recurrenceFrequency,
                    dayInterval:
                        recurrenceFrequency === 'customDays'
                            ? BigInt(recurrenceDayInterval)
                            : undefined,
                    endDate:
                        recurrenceEndDate === ''
                            ? undefined
                            : BigInt(
                                  new Date(
                                      `${recurrenceEndDate}T23:59:59`,
                                  ).getTime(),
                              ),
                    transactionId,
                    type: type === 'income' ? 'income' : 'expense',
                    name: trimmedTitle,
                    description: trimmedDescription,
                    amount: parseAmountToCents(parsedAmount),
                    accountId,
                    categoryId,
                    date: sourceDate,
                    dateConfirmed: true,
                    timeStatus,
                })
            } else if (type === 'income') {
                await createIncome({
                    id: transactionId,
                    name: trimmedTitle,
                    description: trimmedDescription,
                    amount: parseAmountToCents(parsedAmount),
                    accountId,
                    categoryId,
                    date: sourceDate,
                    dateConfirmed: true,
                    timeStatus,
                })
            } else if (type === 'expense') {
                await createExpense({
                    id: transactionId,
                    name: trimmedTitle,
                    description: trimmedDescription,
                    amount: parseAmountToCents(parsedAmount),
                    accountId,
                    categoryId,
                    date: sourceDate,
                    dateConfirmed: true,
                    timeStatus,
                })
            } else {
                const parsedDestinationAmount =
                    parseFormAmount(destinationAmount)
                if (!parsedDestinationAmount) {
                    toast.error(t.addManual.destinationAmountGreaterThanZero)
                    return
                }
                const destinationAccount = accountOptions.find(
                    (account) => account.id === destinationAccountId,
                )
                const exchangeRate =
                    selectedAccount.currency !== destinationAccount?.currency
                        ? computeExchangeRate(
                              parsedAmount,
                              parsedDestinationAmount,
                          )
                        : undefined

                await createTransfer({
                    id: transactionId,
                    name: trimmedTitle,
                    description: trimmedDescription,
                    amount: parseAmountToCents(parsedAmount),
                    accountId,
                    toAccountId: destinationAccountId,
                    toAmount: parseAmountToCents(parsedDestinationAmount),
                    exchangeRate,
                    categoryId,
                    date: sourceDate,
                    dateConfirmed: true,
                    timeStatus,
                })
            }

            if (resolvedTagIds.length > 0) {
                await tagTransaction({
                    transactionId,
                    tagIds: resolvedTagIds,
                })
            }

            toast.success(t.addManual.saved)
            onSaved()
        } catch (error) {
            toast.error(
                error instanceof Error ? error.message : t.addManual.saveFailed,
            )
        } finally {
            setIsSaving(false)
        }
    }

    const isLoading =
        accounts === undefined ||
        categories === undefined ||
        availableTags === undefined

    const addAccount = async (name: string, currency: string) => {
        const normalizedName = normalizeIdentity(name)
        const exists = accountOptions.some(
            (account) =>
                normalizeIdentity(account.name) === normalizedName &&
                account.currency === currency,
        )
        if (exists) {
            toast.error(t.addManual.duplicateAccount)
            return false
        }
        const account: AccountOption = {
            id: newId(),
            name,
            currency,
        }
        await createAccount({
            id: account.id,
            name: account.name,
            currency: account.currency,
        })
        setCreatedAccounts((current) => mergeAccounts(current, [account]))
        setAccountId(account.id)
        return true
    }

    const addCategory = async (name: string) => {
        const normalizedName = normalizeIdentity(name)
        const exists = categoryOptions.some(
            (category) => normalizeIdentity(category.name) === normalizedName,
        )
        if (exists) {
            toast.error(t.addManual.duplicateCategory)
            return false
        }
        const category: CategoryOption = {
            id: newId(),
            name,
        }
        await createCategory({
            id: category.id,
            name: category.name,
        })
        setCreatedCategories((current) => mergeCategories(current, [category]))
        setCategoryId(category.id)
        return true
    }

    if (isLoading) {
        return (
            <FormScreen onClose={onClose}>
                <div className="flex min-h-0 flex-1 items-center justify-center p-6">
                    <CircularProgress isIndeterminate />
                </div>
            </FormScreen>
        )
    }

    /*
     * Field order, spacing and controls are a 1:1 port of the native
     * `TransactionFormScreen.build` (apps/native/lib/screens/transaction_form.dart):
     * a centred display headline, the type segmented button, then account /
     * date / time / amount / title / description / category / tags, closed by
     * the tonal-cancel + filled-record pair. The `SizedBox` heights below are
     * the native ones.
     */
    return (
        <FormScreen onClose={onClose}>
            <form
                onSubmit={(event) => void submit(event)}
                className="flex flex-col px-6 pt-12 pb-8"
            >
                <h2 className="m3-display-small text-center font-extrabold text-on-surface">
                    {t.addManual.newTransaction}
                </h2>

                {/*
                 * The accent follows the *selected* type and is set once for
                 * the whole set, exactly like native's single `selectedColor`
                 * in the segmented button's `ButtonStyle`. It has to live on
                 * the set rather than the segments: Actify's `SegmentedButton`
                 * drops `style`, and custom properties inherit.
                 */}
                <div className="mt-7 flex justify-center">
                    <SegmentedButtonSet
                        className="m3-segmented-set"
                        style={{
                            '--md-outlined-segmented-button-selected-container-color':
                                SELECTED_COLORS[type].background,
                            '--md-outlined-segmented-button-selected-label-text-color':
                                SELECTED_COLORS[type].foreground,
                            '--md-outlined-segmented-button-selected-hover-label-text-color':
                                SELECTED_COLORS[type].foreground,
                            '--md-outlined-segmented-button-selected-focus-label-text-color':
                                SELECTED_COLORS[type].foreground,
                            '--md-outlined-segmented-button-selected-pressed-label-text-color':
                                SELECTED_COLORS[type].foreground,
                            '--md-outlined-segmented-button-selected-icon-color':
                                SELECTED_COLORS[type].foreground,
                            '--md-outlined-segmented-button-label-text-weight':
                                '700',
                        }}
                    >
                        {MOVEMENT_TYPES.map((item) => (
                            <SegmentedButton
                                key={item}
                                label={typeCopy(item, t).label}
                                selected={type === item}
                                noCheckmark
                                onPress={() => changeType(item)}
                            />
                        ))}
                    </SegmentedButtonSet>
                </div>

                <div className="mt-9">
                    {type === 'transfer' ? (
                        <TransferAmounts
                            accounts={accountOptions}
                            sourceAmount={amount}
                            destinationAmount={destinationAmount}
                            sourceAccountId={accountId}
                            destinationAccountId={destinationAccountId}
                            onSourceAmountChange={updateSourceAmount}
                            onDestinationAmountChange={updateDestinationAmount}
                            onSourceAccountChange={updateSourceAccount}
                            onDestinationAccountChange={
                                updateDestinationAccount
                            }
                            onSwap={swapTransferSides}
                        />
                    ) : (
                        // The account picker takes the row, and on an expense
                        // the recurring toggle sits beside it — native's
                        // `Row(Expanded(account), _RecurringExpenseControl)`.
                        <div className="flex items-end gap-4">
                            <div className="min-w-0 flex-1">
                                <AccountSelect
                                    value={accountId}
                                    onChange={setAccountId}
                                    onCreate={() =>
                                        setIsCreateAccountOpen(true)
                                    }
                                    accounts={accountOptions}
                                    label={t.addManual.account}
                                />
                            </div>
                            {showRecurrence ? (
                                <RecurringToggle
                                    label={
                                        type === 'income'
                                            ? t.addManual.recurringIncome
                                            : t.addManual.recurringExpense
                                    }
                                    value={isRecurring}
                                    onChange={setIsRecurring}
                                    isDisabled={isSaving}
                                />
                            ) : null}
                        </div>
                    )}
                </div>

                {showRecurrence && isRecurring ? (
                    <div className="mt-5">
                        <RecurrencePanel
                            frequency={recurrenceFrequency}
                            onFrequencyChange={setRecurrenceFrequency}
                            dayInterval={recurrenceDayInterval}
                            onDayIntervalChange={setRecurrenceDayInterval}
                            endDate={recurrenceEndDate}
                            onEndDateChange={setRecurrenceEndDate}
                            isDisabled={isSaving}
                        />
                    </div>
                ) : null}

                <div className="mt-6">
                    <DateInput value={date} onChange={setDate} />
                </div>
                <div className="mt-4.5">
                    <TimeInput value={time} onChange={setTime} />
                </div>

                {type === 'transfer' ? null : (
                    <>
                        <div className="mt-4.5">
                            <ClearableField
                                id="amount"
                                label={config.amountLabel}
                                value={amount}
                                onChange={(next: string) =>
                                    setAmount(normalizeAmountInput(next))
                                }
                                onClear={() => setAmount('0')}
                                suffixText={selectedAccount?.currency}
                                inputMode="decimal"
                                isRequired
                            />
                        </div>
                        <div className="mt-4.5">
                            <ClearableField
                                id="title"
                                label={t.addManual.title}
                                value={title}
                                onChange={setTitle}
                                onClear={() => setTitle('')}
                                placeholder={
                                    type === 'income'
                                        ? t.addManual.titlePlaceholderIncome
                                        : t.addManual.titlePlaceholderExpense
                                }
                                isRequired
                            />
                        </div>
                    </>
                )}

                <div className="mt-4.5">
                    <ClearableField
                        id="description"
                        label={t.addManual.description}
                        value={description}
                        onChange={setDescription}
                        onClear={() => setDescription('')}
                        placeholder={t.addManual.descriptionPlaceholder}
                        multiline
                    />
                </div>

                <div className="mt-7">
                    <CategorySelect
                        value={categoryId}
                        onChange={setCategoryId}
                        onCreate={() => setIsCreateCategoryOpen(true)}
                        categories={categoryOptions}
                        label={t.addManual.category}
                    />
                </div>

                <div className="mt-6">
                    <TagsField
                        tags={tags}
                        availableTags={knownTags}
                        tagInput={tagInput}
                        onTagInputChange={setTagInput}
                        onAddTag={addTag}
                        onRemoveTag={(name) =>
                            setTags((current) =>
                                current.filter((tag) => tag.name !== name),
                            )
                        }
                    />
                </div>

                <footer className="mt-8 flex gap-4.5">
                    <Button
                        type="button"
                        variant="filled"
                        className="flex-1"
                        // Actify paints the container itself, so the error pair
                        // has to come through the component tokens — a
                        // `bg-*` class loses to its own background. Native does
                        // the same thing via `FilledButton.styleFrom`.
                        style={{
                            '--md-filled-button-container-color':
                                'var(--md-sys-color-error-container)',
                            '--md-filled-button-label-text-color':
                                'var(--md-sys-color-on-error-container)',
                            '--md-filled-button-container-height': '56px',
                        }}
                        onPress={onClose}
                        isDisabled={isSaving}
                    >
                        <Icon name="close" size={18} />
                        {t.common.cancel}
                    </Button>
                    <Button
                        type="submit"
                        variant="filled"
                        className="flex-1"
                        style={{
                            '--md-filled-button-container-height': '56px',
                        }}
                        isDisabled={isSaving}
                    >
                        {isSaving ? (
                            <CircularProgress isIndeterminate size="xs" />
                        ) : (
                            <Icon name="check" size={18} />
                        )}
                        {t.addManual.submit}
                    </Button>
                </footer>
            </form>
            <TagColorDialog
                tagName={pendingTagName}
                selectedColor={pendingTagColor}
                onSelectedColorChange={setPendingTagColor}
                onCancel={() => setPendingTagName(null)}
                onCreate={createPendingTag}
            />
            <CreateEntityDialog
                open={isCreateAccountOpen}
                onOpenChange={setIsCreateAccountOpen}
                title={t.addManual.newAccount}
                namePlaceholder={t.addManual.accountNamePlaceholder}
                successToast={t.addManual.accountAdded}
                withCurrency
                defaultCurrency={settings?.defaultCurrency}
                onCreate={addAccount}
            />
            <CreateEntityDialog
                open={isCreateCategoryOpen}
                onOpenChange={setIsCreateCategoryOpen}
                title={t.addManual.newCategory}
                namePlaceholder={t.addManual.categoryNamePlaceholder}
                successToast={t.addManual.categoryAdded}
                onCreate={(name) => addCategory(name)}
            />
        </FormScreen>
    )
}

/**
 * An outlined text field with the trailing clear action native puts on every
 * text input in this form (`Icons.cancel_outlined` in the decoration's
 * `suffixIcon`).
 *
 * `inputMode` goes through as a top-level prop, never through Actify's
 * `inputProps`: that object *replaces* the field's own input props instead of
 * merging with them, which strips `value`/`onChange` and leaves the field
 * uncontrolled and permanently unpopulated — the label never floats and the
 * text hides behind it on blur.
 */
function ClearableField({
    id,
    label,
    value,
    onChange,
    onClear,
    placeholder,
    suffixText,
    inputMode,
    multiline = false,
    isRequired = false,
}: {
    id?: string
    label: string
    value: string
    onChange: (value: string) => void
    onClear: () => void
    placeholder?: string
    suffixText?: string
    inputMode?: 'decimal' | 'numeric'
    multiline?: boolean
    isRequired?: boolean
}) {
    const t = useT()
    return (
        <div className="relative">
            <TextField
                id={id}
                variant="outlined"
                className="w-full"
                type={multiline ? 'textarea' : 'text'}
                label={label}
                value={value}
                onChange={onChange}
                placeholder={placeholder}
                suffixText={suffixText}
                isRequired={isRequired}
                inputMode={inputMode}
                trailingIcon={
                    value ? (
                        <button
                            type="button"
                            onClick={onClear}
                            aria-label={t.common.clear}
                            className="m3-state-layer flex size-8 cursor-pointer items-center justify-center rounded-full text-on-surface-variant"
                        >
                            <Icon name="cancel" size={20} />
                        </button>
                    ) : undefined
                }
            />
        </div>
    )
}

/** A form section heading, matching native's `_SectionLabel`. */
function SectionLabel({ children }: { children: ReactNode }) {
    return (
        <h2 className="m3-title-large font-extrabold text-on-surface">
            {children}
        </h2>
    )
}

/**
 * The `recurringExpense` flag's toggle, porting native's
 * `_RecurringExpenseControl`: a centred label over a switch, capped narrow so
 * it never crowds the account picker beside it.
 *
 * The flag is registered as "feature not built yet", so this records nothing —
 * flipping it changes no saved transaction, on either client.
 */
function RecurringToggle({
    label,
    value,
    onChange,
    isDisabled,
}: {
    label: string
    value: boolean
    onChange: (value: boolean) => void
    isDisabled: boolean
}) {
    return (
        <div className="flex max-w-33 shrink-0 flex-col items-center gap-1.5">
            <span className="m3-body-medium text-center font-extrabold text-on-surface">
                {label}
            </span>
            <Switch
                aria-label={label}
                isSelected={value}
                onChange={onChange}
                isDisabled={isDisabled}
            />
        </div>
    )
}

/**
 * The recurrence detail panel, porting native's `_RecurrencePanel`: the
 * cadence as choice chips, the day interval when the cadence is "every X
 * days", and an optional end date.
 *
 * Like the toggle above it, the flag is registered as "feature not built
 * yet", so nothing here is persisted on either client.
 */
function RecurrencePanel({
    frequency,
    onFrequencyChange,
    dayInterval,
    onDayIntervalChange,
    endDate,
    onEndDateChange,
    isDisabled,
}: {
    frequency: RecurrenceFrequency
    onFrequencyChange: (value: RecurrenceFrequency) => void
    dayInterval: number
    onDayIntervalChange: (value: number) => void
    endDate: string
    onEndDateChange: (value: string) => void
    isDisabled: boolean
}) {
    const t = useT()
    const horizon = recurrenceHorizon(frequency, dayInterval)
    return (
        <div className="rounded-xl border border-outline-variant bg-surface-container-low p-4">
            <span className="m3-title-small text-on-surface">
                {t.addManual.frequency}
            </span>
            <div className="mt-2.5 flex flex-wrap gap-2">
                {RECURRENCE_FREQUENCIES.map((value) => (
                    <ChoiceChip
                        key={value}
                        label={recurrenceFrequencyLabel(value, t)}
                        selected={frequency === value}
                        onSelect={() => {
                            if (isDisabled) return
                            onFrequencyChange(value)
                        }}
                    />
                ))}
            </div>

            {frequency === 'customDays' ? (
                <div className="mt-4 flex items-center gap-3">
                    <span className="m3-body-large text-on-surface">
                        {t.addManual.recurrenceRepeatEvery}
                    </span>
                    <TextField
                        className="w-20"
                        aria-label={t.addManual.recurrenceRepeatEvery}
                        variant="outlined"
                        inputMode="numeric"
                        value={dayInterval.toString()}
                        isDisabled={isDisabled}
                        onChange={(next: string) => {
                            const parsed = Number.parseInt(next, 10)
                            if (!Number.isFinite(parsed) || parsed < 1) return
                            onDayIntervalChange(parsed)
                        }}
                    />
                    <span className="m3-body-large text-on-surface">
                        {t.addManual.recurrenceDaysUnit}
                    </span>
                </div>
            ) : null}

            <div className="mt-4">
                <DateField
                    id="recurrence-end-date"
                    value={endDate}
                    onChange={onEndDateChange}
                    label={t.addManual.recurrenceEndDateOptional}
                    // The asterisk marks the placeholder, not the label: it is
                    // the *absence* of an end date that the note below
                    // qualifies, so it belongs on the words that say so.
                    placeholder={`${t.addManual.recurrenceNoEndDate}*`}
                    icon="event_repeat"
                    isDisabled={isDisabled}
                    onClear={() => onEndDateChange('')}
                />
            </div>

            {endDate === '' ? (
                <p className="m3-body-small mt-2 text-on-surface-variant">
                    <span aria-hidden>* </span>
                    {t.addManual.recurrenceOpenEndedNote(
                        horizon.count,
                        spanLabel(horizon.span, t),
                    )}
                </p>
            ) : null}
        </div>
    )
}

/** Renders a horizon's reach in the unit the policy chose for it. */
function spanLabel(span: RecurrenceSpan, t: Messages): string {
    switch (span.unit) {
        case 'days':
            return t.addManual.recurrenceSpanDays(span.value)
        case 'months':
            return t.addManual.recurrenceSpanMonths(span.value)
        case 'years':
            return t.addManual.recurrenceSpanYears(span.value)
    }
}

function TransferAmounts({
    accounts,
    sourceAmount,
    destinationAmount,
    sourceAccountId,
    destinationAccountId,
    onSourceAmountChange,
    onDestinationAmountChange,
    onSourceAccountChange,
    onDestinationAccountChange,
    onSwap,
}: {
    accounts: AccountOption[]
    sourceAmount: string
    destinationAmount: string
    sourceAccountId: string
    destinationAccountId: string
    onSourceAmountChange: (value: string) => void
    onDestinationAmountChange: (value: string) => void
    onSourceAccountChange: (value: string) => void
    onDestinationAccountChange: (value: string) => void
    onSwap: () => void
}) {
    const t = useT()
    const sourceAccount = accounts.find(
        (account) => account.id === sourceAccountId,
    )
    const destinationAccount = accounts.find(
        (account) => account.id === destinationAccountId,
    )

    return (
        <section className="space-y-5">
            <div className="grid items-start gap-4 sm:grid-cols-[1fr_auto_1fr]">
                <TransferSide
                    accounts={accounts}
                    label={t.addManual.outgoing}
                    amount={sourceAmount}
                    accountId={sourceAccountId}
                    currency={sourceAccount?.currency}
                    onAmountChange={onSourceAmountChange}
                    onAccountChange={onSourceAccountChange}
                />
                <div className="flex justify-center pt-10">
                    <IconButton
                        aria-label={t.addManual.swapSides}
                        onPress={onSwap}
                        className="bg-primary-container text-on-primary-container"
                    >
                        <Icon name="swap_vert" filled size={20} />
                    </IconButton>
                </div>
                <TransferSide
                    accounts={accounts}
                    label={t.addManual.incoming}
                    amount={destinationAmount}
                    accountId={destinationAccountId}
                    currency={destinationAccount?.currency}
                    onAmountChange={onDestinationAmountChange}
                    onAccountChange={onDestinationAccountChange}
                />
            </div>
        </section>
    )
}

function TransferSide({
    accounts,
    label,
    amount,
    accountId,
    currency,
    onAmountChange,
    onAccountChange,
}: {
    accounts: AccountOption[]
    label: string
    amount: string
    accountId: string
    currency?: string
    onAmountChange: (value: string) => void
    onAccountChange: (value: string) => void
}) {
    return (
        <div className="flex flex-col gap-3">
            <p className="m3-label-large text-center font-extrabold text-on-surface-variant">
                {label}
            </p>
            <TextField
                variant="outlined"
                className="w-full"
                aria-label={label}
                label={label}
                value={amount}
                onChange={(next: string) =>
                    onAmountChange(normalizeAmountInput(next))
                }
                suffixText={currency}
                inputMode="decimal"
                isRequired
            />
            <AccountSelect
                value={accountId}
                onChange={onAccountChange}
                accounts={accounts}
                label={label}
            />
        </div>
    )
}

function TagsField({
    tags,
    availableTags,
    tagInput,
    onTagInputChange,
    onAddTag,
    onRemoveTag,
}: {
    tags: FormTag[]
    availableTags: FormTag[]
    tagInput: string
    onTagInputChange: (value: string) => void
    onAddTag: (value: string) => void
    onRemoveTag: (name: string) => void
}) {
    const t = useT()
    const [pickerOpen, setPickerOpen] = useState(false)
    const [creating, setCreating] = useState(false)

    const selectable = availableTags.filter(
        (tag) =>
            !tags.some(
                (selected) =>
                    selected.name.toLowerCase() === tag.name.toLowerCase(),
            ),
    )

    return (
        <section className="flex flex-col gap-2.5">
            <SectionLabel>{t.addManual.tags}</SectionLabel>
            <PickerChip
                label={t.addManual.addTag}
                onClick={() => setPickerOpen(true)}
            />

            {tags.length > 0 ? (
                <div className="flex flex-wrap gap-2">
                    {tags.map((tag) => (
                        <TagChip
                            key={tag.id ?? tag.name}
                            name={tag.name}
                            color={tag.color}
                            trailing={
                                <button
                                    type="button"
                                    aria-label={t.common.delete}
                                    onClick={() => onRemoveTag(tag.name)}
                                    className="flex cursor-pointer items-center"
                                >
                                    <Icon name="close" size={16} />
                                </button>
                            }
                        />
                    ))}
                </div>
            ) : null}

            <OptionSheet
                open={pickerOpen}
                onOpenChange={setPickerOpen}
                title={t.addManual.tags}
                options={selectable.map((tag) => ({
                    id: tag.name,
                    label: tag.name,
                    leading: (
                        <span
                            aria-hidden
                            className="size-6 shrink-0 rounded-full"
                            style={{ backgroundColor: tag.color }}
                        />
                    ),
                }))}
                selected={null}
                onSelect={(name) => {
                    onAddTag(name)
                    setPickerOpen(false)
                }}
                searchPlaceholder={t.insights.searchTags}
                emptyMessage={t.insights.noTagsAvailable}
                header={
                    <NewEntityRow
                        label={t.insights.newTag}
                        onClick={() => {
                            setPickerOpen(false)
                            setCreating(true)
                        }}
                    />
                }
            />

            <M3Dialog
                open={creating}
                onOpenChange={(open) => {
                    if (!open) {
                        setCreating(false)
                        onTagInputChange('')
                    }
                }}
                title={t.insights.newTag}
                onKeyDownCapture={(event) => {
                    if (event.key !== 'Enter' || !tagInput.trim()) return
                    event.preventDefault()
                    setCreating(false)
                    onAddTag(tagInput)
                }}
                actions={
                    <>
                        <DialogAction
                            label={t.common.cancel}
                            onPress={() => {
                                setCreating(false)
                                onTagInputChange('')
                            }}
                        />
                        <DialogAction
                            label={t.common.create}
                            isDisabled={!tagInput.trim()}
                            onPress={() => {
                                setCreating(false)
                                onAddTag(tagInput)
                            }}
                        />
                    </>
                }
            >
                <TextField
                    variant="outlined"
                    className="w-full"
                    label={t.insights.newTag}
                    value={tagInput}
                    onChange={onTagInputChange}
                    placeholder={t.addManual.addTag}
                    autoFocus
                />
            </M3Dialog>
        </section>
    )
}

function TagColorDialog({
    tagName,
    selectedColor,
    onSelectedColorChange,
    onCancel,
    onCreate,
}: {
    tagName: string | null
    selectedColor: string
    onSelectedColorChange: (color: string) => void
    onCancel: () => void
    onCreate: () => Promise<void>
}) {
    const t = useT()
    return (
        <M3Dialog
            open={tagName !== null}
            onOpenChange={(open) => !open && onCancel()}
            title={t.addManual.tagColorTitle({ name: tagName ?? '' })}
            onKeyDownCapture={(event) => {
                if (event.key !== 'Enter') return
                event.preventDefault()
                void onCreate()
            }}
            actions={
                <>
                    <DialogAction label={t.common.cancel} onPress={onCancel} />
                    <DialogAction
                        label={t.common.create}
                        onPress={() => void onCreate()}
                    />
                </>
            }
        >
            <ColorSwatches
                value={selectedColor}
                onChange={onSelectedColorChange}
                options={TAG_COLOR_OPTIONS}
            />
        </M3Dialog>
    )
}

/**
 * The filled pill native uses to open a picker (`_PickerChip`): bright brand
 * container, stadium shape, a caret in front of the current value.
 */
function PickerChip({
    label,
    onClick,
}: {
    label: string
    onClick: () => void
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            className="m3-state-layer flex max-w-[55%] cursor-pointer items-center gap-2 self-start rounded-full bg-primary-container px-3.5 py-2.5 font-bold text-[15px] text-on-primary-container"
        >
            <Icon name="keyboard_arrow_down" size={20} className="shrink-0" />
            <span className="truncate">{label}</span>
        </button>
    )
}

/** The labeled chip + option-sheet picker both entity selects share. */
function EntitySelect({
    label,
    chipLabel,
    options,
    value,
    onChange,
    searchPlaceholder,
    createLabel,
    onCreate,
}: {
    label: string
    chipLabel: string
    options: SheetOption[]
    value: string
    onChange: (value: string) => void
    searchPlaceholder: string
    createLabel: string
    onCreate?: () => void
}) {
    const [open, setOpen] = useState(false)
    return (
        <section className="flex flex-col gap-2.5">
            <SectionLabel>{label}</SectionLabel>
            <PickerChip label={chipLabel} onClick={() => setOpen(true)} />
            <OptionSheet
                open={open}
                onOpenChange={setOpen}
                title={label}
                options={options}
                selected={value === '' ? null : value}
                onSelect={(id) => {
                    onChange(id)
                    setOpen(false)
                }}
                searchPlaceholder={searchPlaceholder}
                header={
                    onCreate ? (
                        <NewEntityRow
                            label={createLabel}
                            onClick={() => {
                                setOpen(false)
                                onCreate()
                            }}
                        />
                    ) : null
                }
            />
        </section>
    )
}

function AccountSelect({
    value,
    onChange,
    onCreate,
    accounts,
    label,
}: {
    value: string
    onChange: (value: string) => void
    onCreate?: () => void
    accounts: AccountOption[]
    label: string
}) {
    const t = useT()
    const selected = accounts.find((account) => account.id === value)
    return (
        <EntitySelect
            label={label}
            chipLabel={
                selected
                    ? `${selected.name} · ${selected.currency}`
                    : t.addManual.select
            }
            options={accounts.map((account) => ({
                id: account.id,
                label: account.name,
                supporting: account.currency,
            }))}
            value={value}
            onChange={onChange}
            searchPlaceholder={t.addManual.account}
            createLabel={t.addManual.newAccount}
            onCreate={onCreate}
        />
    )
}

function CategorySelect({
    value,
    onChange,
    onCreate,
    categories,
    label,
}: {
    value: string
    onChange: (value: string) => void
    onCreate: () => void
    categories: CategoryOption[]
    label: string
}) {
    const t = useT()
    const selected = categories.find((category) => category.id === value)
    return (
        <EntitySelect
            label={label}
            chipLabel={selected?.name ?? t.addManual.select}
            options={categories.map((category) => ({
                id: category.id,
                label: category.name,
            }))}
            value={value}
            onChange={onChange}
            searchPlaceholder={label}
            createLabel={t.addManual.newCategory}
            onCreate={onCreate}
        />
    )
}

function NewEntityRow({
    label,
    onClick,
}: {
    label: string
    onClick: () => void
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            className="m3-state-layer flex w-full cursor-pointer items-center gap-4 rounded-2xl px-3 py-3 text-left text-on-surface"
        >
            <Icon name="add_circle" className="text-on-surface-variant" />
            <span className="m3-body-large flex-1">{label}</span>
        </button>
    )
}

function DateInput({
    value,
    onChange,
}: {
    value: string
    onChange: (value: string) => void
}) {
    const t = useT()
    return (
        <DateField
            id="date"
            value={value}
            onChange={onChange}
            label={t.common.date}
            icon="calendar_month"
            onClear={() => onChange(today())}
        />
    )
}

function TimeInput({
    value,
    onChange,
}: {
    value: string
    onChange: (value: string) => void
}) {
    const t = useT()
    const [open, setOpen] = useState(false)
    return (
        <>
            <PickerField
                label={t.addManual.timeOptional}
                value={value}
                placeholder={t.addManual.noTime}
                icon="schedule"
                onClick={() => setOpen(true)}
                onClear={value ? () => onChange('') : undefined}
                clearLabel={t.addManual.removeTime}
            />
            <M3Dialog
                open={open}
                onOpenChange={setOpen}
                title={t.addManual.timeOptional}
                actions={
                    <DialogAction
                        label={t.common.done}
                        onPress={() => setOpen(false)}
                    />
                }
            >
                <TimeField
                    value={value}
                    onChange={onChange}
                    label={t.addManual.timeOptional}
                />
            </M3Dialog>
        </>
    )
}

/**
 * The inline "new account / new category" dialog — one component, since the
 * two differed only by copy and the account's currency picker.
 */
function CreateEntityDialog({
    open,
    onOpenChange,
    title,
    namePlaceholder,
    successToast,
    withCurrency = false,
    defaultCurrency,
    onCreate,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    title: string
    namePlaceholder: string
    successToast: string
    /** Adds the currency picker; `onCreate` receives its value only then. */
    withCurrency?: boolean
    /** The user's default currency, or undefined while settings are loading. */
    defaultCurrency?: string
    onCreate: (name: string, currency: string) => Promise<boolean>
}) {
    const t = useT()
    const [name, setName] = useState('')
    // Null until the user picks one, so the field tracks the real default as it
    // loads instead of sticking on the placeholder — the same rule native's
    // create-account screen uses (`_currency ?? DefaultCurrencyController`).
    const [pickedCurrency, setPickedCurrency] = useState<string | null>(null)
    const currency = pickedCurrency ?? defaultCurrency ?? DEFAULT_CURRENCY
    const [isSubmitting, setIsSubmitting] = useState(false)

    const handleCreate = async () => {
        const trimmed = name.trim()
        if (!trimmed) return
        setIsSubmitting(true)
        let created: boolean
        try {
            created = await onCreate(trimmed, currency)
        } catch {
            // A rejected mutation used to skip the reset below, leaving both
            // dialog buttons disabled forever with no feedback.
            toast.error(t.common.saveFailed)
            return
        } finally {
            setIsSubmitting(false)
        }
        if (!created) return
        setName('')
        setPickedCurrency(null)
        onOpenChange(false)
        toast.success(successToast)
    }

    return (
        <M3Dialog
            open={open}
            onOpenChange={onOpenChange}
            title={title}
            actions={
                <>
                    <DialogAction
                        label={t.common.cancel}
                        onPress={() => onOpenChange(false)}
                        isDisabled={isSubmitting}
                    />
                    <DialogAction
                        label={t.common.create}
                        onPress={() => void handleCreate()}
                        isDisabled={isSubmitting}
                    />
                </>
            }
        >
            <form
                className="flex flex-col gap-4"
                onSubmit={(event) => {
                    event.preventDefault()
                    void handleCreate()
                }}
            >
                <TextField
                    variant="outlined"
                    className="w-full"
                    label={t.common.name}
                    value={name}
                    onChange={setName}
                    placeholder={namePlaceholder}
                    autoFocus
                />
                {withCurrency ? (
                    <CurrencyField
                        id="new-account-currency"
                        value={currency}
                        onChange={setPickedCurrency}
                    />
                ) : null}
            </form>
        </M3Dialog>
    )
}

/**
 * Currency chooser for the inline account dialog, as a picker sheet. Offers the
 * whole shared catalog with the common codes on top — the same list and the
 * same sheet the full create-account form uses, so an account created inline
 * isn't limited to a shorter set of currencies than one created from
 * `/accounts/new`.
 */
function CurrencyField({
    id,
    value,
    onChange,
}: {
    id: string
    value: string
    onChange: (value: string) => void
}) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const [open, setOpen] = useState(false)
    const options: SheetOption[] = useMemo(
        () =>
            CURRENCY_CODES.map((code) => ({
                id: code,
                label: code,
                supporting: currencyName(code, formatLocale),
            })),
        [formatLocale],
    )
    return (
        <>
            <PickerField
                id={id}
                label={t.common.currency}
                value={value}
                onClick={() => setOpen(true)}
            />
            <OptionSheet
                open={open}
                onOpenChange={setOpen}
                title={t.accounts.chooseCurrency}
                options={options}
                selected={value}
                onSelect={(code) => {
                    onChange(code)
                    setOpen(false)
                }}
                searchPlaceholder={t.accounts.searchCurrency}
                suggested={SUGGESTED_CURRENCIES}
            />
        </>
    )
}
