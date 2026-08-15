import { api } from '@wallet-bot/backend/api'
import { parseAmountToCents, parseTransactionDate } from '@wallet-bot/shared'
import { CircularProgress, IconButton } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { type FormEvent, type ReactNode, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
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
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { type Messages, useT } from '@/lib/i18n'
import { TAG_COLOR_OPTIONS } from '@/lib/tag-colors'
import { cn } from '@/lib/utils'

type MovementType = 'income' | 'expense' | 'transfer'

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
const SELECTED_COLORS: Record<MovementType, string> = {
    income: 'bg-[#00E676] text-black',
    expense: 'bg-[#FF3744] text-white',
    transfer: 'bg-[#6DE7D8] text-black',
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

function newId() {
    return crypto.randomUUID()
}

const MOCK_CURRENCIES = ['ARS', 'USD', 'EUR', 'BRL'] as const

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

export function AddManual() {
    const navigate = useNavigate()
    const t = useT()

    const accounts = useQuery(api.v1.accounts.queries.listActive)
    const categories = useQuery(api.v1.categories.queries.listActive)
    const availableTags = useQuery(api.v1.tags.queries.listActive)

    const createIncome = useMutation(api.v1.transactions.mutations.createIncome)
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
    const [saved, setSaved] = useState(false)
    const [isSaving, setIsSaving] = useState(false)

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
        setSaved(false)
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
        await createTag({
            id: createdTag.id,
            name: createdTag.name,
            color: createdTag.color,
        })
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
            if (type === 'income') {
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
                    setIsSaving(false)
                    return
                }
                const destinationAccount = accountOptions.find(
                    (account) => account.id === destinationAccountId,
                )
                const exchangeRate =
                    selectedAccount.currency !== destinationAccount?.currency
                        ? parsedDestinationAmount / parsedAmount
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

            setSaved(true)
            toast.success(t.addManual.saved)
            navigate('/activity')
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

    const appBar = (
        <AppBar
            title={config.title}
            leading={
                <IconButton
                    aria-label={t.common.goBack}
                    onPress={() => navigate(-1)}
                    className="text-on-surface-variant"
                >
                    <Icon name="arrow_back" />
                </IconButton>
            }
        />
    )

    if (isLoading) {
        return (
            <>
                {appBar}
                <div className="flex min-h-0 flex-1 items-center justify-center bg-surface px-4 py-10">
                    <CircularProgress isIndeterminate />
                </div>
            </>
        )
    }

    return (
        <>
            {appBar}
            <div className="flex min-h-0 flex-1 justify-center overflow-y-auto bg-surface px-4 py-10">
                <form
                    onSubmit={(event) => void submit(event)}
                    className="flex w-full max-w-xl flex-col gap-10"
                >
                    <header className="space-y-6 text-center">
                        <div className="inline-flex rounded-full border border-outline-variant bg-surface-container-lowest p-1 shadow-sm">
                            {MOVEMENT_TYPES.map((item) => (
                                <button
                                    key={item}
                                    type="button"
                                    onClick={() => changeType(item)}
                                    className={cn(
                                        'rounded-full px-4 py-2 text-sm font-bold text-on-surface transition-colors',
                                        type === item
                                            ? SELECTED_COLORS[item]
                                            : 'hover:bg-on-surface/8',
                                    )}
                                >
                                    {typeCopy(item, t).label}
                                </button>
                            ))}
                        </div>

                        <p className="m3-body-medium text-on-surface-variant">
                            {config.description}
                        </p>
                    </header>

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
                            date={date}
                            onDateChange={setDate}
                            time={time}
                            onTimeChange={setTime}
                        />
                    ) : (
                        <section className="space-y-5">
                            <div className="space-y-2">
                                <Label
                                    htmlFor="amount"
                                    className="text-base font-bold"
                                >
                                    {config.amountLabel}
                                </Label>
                                <div className="relative">
                                    <Input
                                        id="amount"
                                        inputMode="decimal"
                                        value={amount}
                                        onFocus={() => {
                                            if (amount === '0') setAmount('')
                                        }}
                                        onBlur={() => {
                                            if (amount.trim() === '')
                                                setAmount('0')
                                        }}
                                        onChange={(event) =>
                                            setAmount(
                                                normalizeAmountInput(
                                                    event.target.value,
                                                ),
                                            )
                                        }
                                        placeholder="0,00"
                                        className="h-16 rounded-xl border-outline-variant bg-surface-container-lowest px-20 text-center text-4xl font-normal text-on-surface shadow-sm"
                                        required
                                    />
                                    <span className="absolute top-1/2 right-4 -translate-y-1/2 text-sm font-bold text-muted-foreground">
                                        {selectedAccount?.currency}
                                    </span>
                                </div>
                            </div>

                            <div className="grid gap-5 sm:grid-cols-2">
                                <Field
                                    label={t.addManual.account}
                                    htmlFor="account"
                                    action={
                                        <div className="flex items-center gap-2">
                                            <Button
                                                type="button"
                                                variant="outline"
                                                size="sm"
                                                className="h-8 rounded-full"
                                                onClick={() => setAccountId('')}
                                                disabled={!accountId}
                                            >
                                                <Icon name="close" size={12} />
                                            </Button>
                                            <Button
                                                type="button"
                                                variant="outline"
                                                size="sm"
                                                className="h-8 rounded-full"
                                                onClick={() =>
                                                    setIsCreateAccountOpen(true)
                                                }
                                            >
                                                <Icon name="add" size={12} />
                                                {t.addManual.newAccount}
                                            </Button>
                                        </div>
                                    }
                                >
                                    <AccountSelect
                                        id="account"
                                        value={accountId}
                                        onChange={setAccountId}
                                        accounts={accountOptions}
                                    />
                                </Field>

                                <Field label={t.addManual.date} htmlFor="date">
                                    <DateInput
                                        value={date}
                                        onChange={setDate}
                                    />
                                </Field>

                                <Field
                                    label={t.addManual.timeOptional}
                                    htmlFor="time"
                                >
                                    <TimeInput
                                        value={time}
                                        onChange={setTime}
                                    />
                                </Field>
                            </div>
                        </section>
                    )}

                    <section className="space-y-5">
                        <Field label={t.addManual.title} htmlFor="title">
                            <Input
                                id="title"
                                value={title}
                                onChange={(event) =>
                                    setTitle(event.target.value)
                                }
                                placeholder={
                                    type === 'transfer'
                                        ? t.addManual.titlePlaceholderTransfer
                                        : type === 'income'
                                          ? t.addManual.titlePlaceholderIncome
                                          : t.addManual.titlePlaceholderExpense
                                }
                                className="h-11 rounded-xl border-outline-variant bg-surface-container-lowest"
                                required={type !== 'transfer'}
                            />
                        </Field>

                        <Field
                            label={t.addManual.description}
                            htmlFor="description"
                        >
                            <Textarea
                                id="description"
                                value={description}
                                onChange={(event) =>
                                    setDescription(event.target.value)
                                }
                                placeholder={t.addManual.descriptionPlaceholder}
                                rows={3}
                                className="rounded-xl border-outline-variant bg-surface-container-lowest"
                            />
                        </Field>

                        <Field
                            label={t.addManual.category}
                            htmlFor="category"
                            action={
                                <div className="flex items-center gap-2">
                                    <Button
                                        type="button"
                                        variant="outline"
                                        size="sm"
                                        className="h-8 rounded-full"
                                        onClick={() => setCategoryId('')}
                                        disabled={!categoryId}
                                    >
                                        <Icon name="close" size={12} />
                                    </Button>
                                    <Button
                                        type="button"
                                        variant="outline"
                                        size="sm"
                                        className="h-8 rounded-full"
                                        onClick={() =>
                                            setIsCreateCategoryOpen(true)
                                        }
                                    >
                                        <Icon name="add" size={12} />
                                        {t.addManual.newCategory}
                                    </Button>
                                </div>
                            }
                        >
                            <select
                                id="category"
                                value={categoryId}
                                onChange={(event) =>
                                    setCategoryId(event.target.value)
                                }
                                className="h-11 w-full rounded-xl border border-outline-variant bg-surface-container-lowest px-3 text-sm outline-none focus-visible:border-primary focus-visible:ring-3 focus-visible:ring-primary/30"
                                required
                            >
                                <option value="">
                                    {t.addManual.unselected}
                                </option>
                                {categoryOptions.map((item) => (
                                    <option key={item.id} value={item.id}>
                                        {item.name}
                                    </option>
                                ))}
                            </select>
                        </Field>
                    </section>

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

                    {saved ? (
                        <div className="rounded-xl bg-secondary-container px-4 py-3 text-sm font-medium text-on-secondary-container">
                            {t.addManual.savedNote}
                        </div>
                    ) : null}

                    <footer className="flex gap-3 pt-2">
                        <Button
                            type="button"
                            variant="outline"
                            className="h-12 flex-1 rounded-xl border-error-container bg-error-container text-on-error-container hover:opacity-90"
                            onClick={() => resetFields()}
                            disabled={isSaving}
                        >
                            <Icon name="close" size={16} />
                            {t.common.cancel}
                        </Button>
                        <Button
                            type="submit"
                            className="h-12 flex-1 rounded-xl bg-primary-container text-on-primary-container hover:opacity-90"
                            disabled={isSaving}
                        >
                            {isSaving ? (
                                <CircularProgress isIndeterminate size="xs" />
                            ) : (
                                <Icon name="check" size={16} />
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
                <CreateAccountDialog
                    open={isCreateAccountOpen}
                    onOpenChange={setIsCreateAccountOpen}
                    onCreate={addAccount}
                />
                <CreateCategoryDialog
                    open={isCreateCategoryOpen}
                    onOpenChange={setIsCreateCategoryOpen}
                    onCreate={addCategory}
                />
            </div>
        </>
    )
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
    date,
    onDateChange,
    time,
    onTimeChange,
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
    date: string
    onDateChange: (value: string) => void
    time: string
    onTimeChange: (value: string) => void
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
                    <Button
                        type="button"
                        variant="outline"
                        onClick={onSwap}
                        aria-label={t.addManual.swapSides}
                        className="size-11 rounded-full border-outline-variant bg-primary-container/40 p-0 text-on-surface hover:bg-primary-container/60"
                    >
                        <Icon name="swap_vert" filled size={20} />
                    </Button>
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

            <div className="grid gap-5 sm:grid-cols-2">
                <Field label={t.addManual.date} htmlFor="date">
                    <DateInput value={date} onChange={onDateChange} />
                </Field>
                <Field label={t.addManual.timeOptional} htmlFor="time">
                    <TimeInput value={time} onChange={onTimeChange} />
                </Field>
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
        <div className="space-y-3">
            <Label className="block text-base font-black text-on-surface">
                {label}
            </Label>
            <div className="relative">
                <Input
                    inputMode="decimal"
                    value={amount}
                    onFocus={() => {
                        if (amount === '0') onAmountChange('')
                    }}
                    onBlur={() => {
                        if (amount.trim() === '') onAmountChange('0')
                    }}
                    onChange={(event) =>
                        onAmountChange(normalizeAmountInput(event.target.value))
                    }
                    placeholder="0,00"
                    className="h-13 rounded-xl border-outline-variant bg-surface-container-lowest px-14 text-center text-2xl font-normal text-on-surface shadow-sm"
                    required
                />
                <span className="absolute top-1/2 right-3 -translate-y-1/2 text-xs font-bold text-muted-foreground">
                    {currency}
                </span>
            </div>
            <AccountSelect
                value={accountId}
                onChange={onAccountChange}
                accounts={accounts}
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
    return (
        <section className="space-y-4">
            <Field label={t.addManual.tags} htmlFor="tags">
                <div className="flex gap-2">
                    <Input
                        id="tags"
                        value={tagInput}
                        onChange={(event) =>
                            onTagInputChange(event.target.value)
                        }
                        onKeyDown={(event) => {
                            if (event.key === 'Enter' || event.key === ',') {
                                event.preventDefault()
                                onAddTag(tagInput)
                            }
                        }}
                        placeholder={t.addManual.addTag}
                        className="h-11 rounded-xl border-outline-variant bg-surface-container-lowest"
                    />
                    <Button
                        type="button"
                        variant="outline"
                        onClick={() => onAddTag(tagInput)}
                        className="h-11 rounded-xl border-outline-variant bg-surface-container-lowest"
                    >
                        <Icon name="add" size={16} />
                    </Button>
                </div>
            </Field>

            <div className="flex flex-wrap gap-2">
                {availableTags.map((tag) => (
                    <button
                        key={tag.id ?? tag.name}
                        type="button"
                        onClick={() => onAddTag(tag.name)}
                        className="h-8 rounded-full border px-3 text-sm font-medium"
                        style={{
                            backgroundColor: tag.color,
                            borderColor: tag.color,
                            color: '#111',
                        }}
                    >
                        {tag.name}
                    </button>
                ))}
            </div>

            {tags.length > 0 ? (
                <div className="flex flex-wrap gap-2">
                    {tags.map((tag) => (
                        <Badge
                            key={tag.id ?? tag.name}
                            variant="secondary"
                            className="h-7 gap-1 rounded-full text-on-surface"
                            style={{ backgroundColor: tag.color }}
                        >
                            {tag.name}
                            <button
                                type="button"
                                onClick={() => onRemoveTag(tag.name)}
                            >
                                <Icon name="close" size={12} />
                            </button>
                        </Badge>
                    ))}
                </div>
            ) : null}
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
        <Dialog
            open={tagName !== null}
            onOpenChange={(open) => !open && onCancel()}
        >
            <DialogContent
                onKeyDownCapture={(event) => {
                    if (event.key !== 'Enter') return
                    event.preventDefault()
                    void onCreate()
                }}
            >
                <form
                    onSubmit={(event) => {
                        event.preventDefault()
                        void onCreate()
                    }}
                >
                    <DialogHeader>
                        <DialogTitle>
                            {t.addManual.tagColorTitle({ name: tagName ?? '' })}
                        </DialogTitle>
                    </DialogHeader>
                    <div className="flex flex-wrap gap-3 py-2">
                        {TAG_COLOR_OPTIONS.map((color) => (
                            <button
                                key={color}
                                type="button"
                                aria-label={t.addManual.chooseColor({ color })}
                                onClick={() => onSelectedColorChange(color)}
                                className={cn(
                                    'flex size-10 items-center justify-center rounded-full border-2',
                                    color === selectedColor
                                        ? 'border-black'
                                        : 'border-transparent',
                                )}
                                style={{ backgroundColor: color }}
                            >
                                {color === selectedColor ? (
                                    <Icon
                                        name="check"
                                        size={20}
                                        className="text-on-surface"
                                    />
                                ) : null}
                            </button>
                        ))}
                    </div>
                    <DialogFooter>
                        <Button
                            type="button"
                            variant="outline"
                            onClick={onCancel}
                        >
                            {t.common.cancel}
                        </Button>
                        <Button
                            type="submit"
                            className="bg-primary-container text-on-primary-container hover:opacity-90"
                            autoFocus
                        >
                            {t.common.create}
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    )
}

function AccountSelect({
    id,
    value,
    onChange,
    accounts,
}: {
    id?: string
    value: string
    onChange: (value: string) => void
    accounts: AccountOption[]
}) {
    const t = useT()
    return (
        <select
            id={id}
            value={value}
            onChange={(event) => onChange(event.target.value)}
            className="h-11 w-full rounded-xl border border-outline-variant bg-surface-container-lowest px-3 text-sm outline-none focus-visible:border-primary focus-visible:ring-3 focus-visible:ring-primary/30"
        >
            <option value="">{t.addManual.unselected}</option>
            {accounts.map((account) => (
                <option key={account.id} value={account.id}>
                    {account.name} · {account.currency}
                </option>
            ))}
        </select>
    )
}

function DateInput({
    value,
    onChange,
}: {
    value: string
    onChange: (value: string) => void
}) {
    return (
        <Input
            id="date"
            type="date"
            value={value}
            onChange={(event) => onChange(event.target.value)}
            className="h-11 rounded-xl border-outline-variant bg-surface-container-lowest"
            required
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
    return (
        <div className="flex gap-2">
            <Input
                id="time"
                type="time"
                value={value}
                onChange={(event) => onChange(event.target.value)}
                className="h-11 rounded-xl border-outline-variant bg-surface-container-lowest"
            />
            {value ? (
                <Button
                    type="button"
                    variant="outline"
                    size="icon"
                    className="h-11 w-11 shrink-0 rounded-xl border-outline-variant bg-surface-container-lowest"
                    onClick={() => onChange('')}
                    aria-label={t.addManual.removeTime}
                >
                    <Icon name="close" size={16} />
                </Button>
            ) : null}
        </div>
    )
}

function Field({
    label,
    htmlFor,
    action,
    children,
}: {
    label: string
    htmlFor?: string
    action?: ReactNode
    children: ReactNode
}) {
    return (
        <div className="space-y-2">
            <div className="flex items-center justify-between gap-3">
                <Label
                    htmlFor={htmlFor}
                    className="text-base font-bold text-on-surface"
                >
                    {label}
                </Label>
                {action}
            </div>
            {children}
        </div>
    )
}

function CreateAccountDialog({
    open,
    onOpenChange,
    onCreate,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    onCreate: (name: string, currency: string) => Promise<boolean>
}) {
    const t = useT()
    const [name, setName] = useState('')
    const [currency, setCurrency] =
        useState<(typeof MOCK_CURRENCIES)[number]>('ARS')
    const [isSubmitting, setIsSubmitting] = useState(false)

    const handleCreate = async () => {
        const trimmed = name.trim()
        if (!trimmed) return
        setIsSubmitting(true)
        const created = await onCreate(trimmed, currency)
        setIsSubmitting(false)
        if (!created) return
        setName('')
        setCurrency('ARS')
        onOpenChange(false)
        toast.success(t.addManual.accountAdded)
    }

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>{t.addManual.newAccount}</DialogTitle>
                </DialogHeader>
                <form
                    className="space-y-4"
                    onSubmit={(event) => {
                        event.preventDefault()
                        handleCreate()
                    }}
                >
                    <Field label={t.common.name} htmlFor="mock-account-name">
                        <Input
                            id="mock-account-name"
                            value={name}
                            onChange={(event) => setName(event.target.value)}
                            placeholder={t.addManual.accountNamePlaceholder}
                        />
                    </Field>
                    <Field
                        label={t.common.currency}
                        htmlFor="mock-account-currency"
                    >
                        <select
                            id="mock-account-currency"
                            value={currency}
                            onChange={(event) =>
                                setCurrency(
                                    event.target
                                        .value as (typeof MOCK_CURRENCIES)[number],
                                )
                            }
                            className="h-11 w-full rounded-xl border border-outline-variant bg-surface-container-lowest px-3 text-sm outline-none focus-visible:border-primary focus-visible:ring-3 focus-visible:ring-primary/30"
                        >
                            {MOCK_CURRENCIES.map((option) => (
                                <option key={option} value={option}>
                                    {option}
                                </option>
                            ))}
                        </select>
                    </Field>
                </form>
                <DialogFooter>
                    <Button
                        type="button"
                        variant="outline"
                        onClick={() => onOpenChange(false)}
                        disabled={isSubmitting}
                    >
                        {t.common.cancel}
                    </Button>
                    <Button
                        type="button"
                        onClick={() => void handleCreate()}
                        disabled={isSubmitting}
                    >
                        {t.common.create}
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    )
}

function CreateCategoryDialog({
    open,
    onOpenChange,
    onCreate,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    onCreate: (name: string) => Promise<boolean>
}) {
    const t = useT()
    const [name, setName] = useState('')
    const [isSubmitting, setIsSubmitting] = useState(false)

    const handleCreate = async () => {
        const trimmed = name.trim()
        if (!trimmed) return
        setIsSubmitting(true)
        const created = await onCreate(trimmed)
        setIsSubmitting(false)
        if (!created) return
        setName('')
        onOpenChange(false)
        toast.success(t.addManual.categoryAdded)
    }

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>{t.addManual.newCategory}</DialogTitle>
                </DialogHeader>
                <form
                    onSubmit={(event) => {
                        event.preventDefault()
                        handleCreate()
                    }}
                >
                    <Field label={t.common.name} htmlFor="mock-category-name">
                        <Input
                            id="mock-category-name"
                            value={name}
                            onChange={(event) => setName(event.target.value)}
                            placeholder={t.addManual.categoryNamePlaceholder}
                        />
                    </Field>
                </form>
                <DialogFooter>
                    <Button
                        type="button"
                        variant="outline"
                        onClick={() => onOpenChange(false)}
                        disabled={isSubmitting}
                    >
                        {t.common.cancel}
                    </Button>
                    <Button
                        type="button"
                        onClick={() => void handleCreate()}
                        disabled={isSubmitting}
                    >
                        {t.common.create}
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    )
}
