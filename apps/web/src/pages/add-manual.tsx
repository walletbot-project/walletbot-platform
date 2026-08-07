import { api } from '@wallet-bot/backend/api'
import { parseAmountToCents, parseTransactionDate } from '@wallet-bot/shared'
import { useMutation, useQuery } from 'convex/react'
import { Check, Loader2, Plus, Repeat2, X } from 'lucide-react'
import { type FormEvent, type ReactNode, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
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
import { Switch } from '@/components/ui/switch'
import { Textarea } from '@/components/ui/textarea'
import { TAG_COLOR_OPTIONS } from '@/lib/tag-colors'
import { cn } from '@/lib/utils'

type MovementType = 'income' | 'expense' | 'transfer'

type RecurrenceFrequency =
    | 'daily'
    | 'weekly'
    | 'monthly'
    | 'yearly'
    | 'customDays'

const DEFAULT_RECURRENCE_DAY_INTERVAL = 15

const RECURRENCE_FREQUENCY_OPTIONS: {
    value: RecurrenceFrequency
    label: string
}[] = [
    { value: 'daily', label: 'Diario' },
    { value: 'weekly', label: 'Semanal' },
    { value: 'monthly', label: 'Mensual' },
    { value: 'yearly', label: 'Anual' },
    { value: 'customDays', label: 'Cada X días' },
]

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

const typeConfig: Record<
    MovementType,
    {
        label: string
        title: string
        description: string
        amountLabel: string
        selectedColor: string
    }
> = {
    income: {
        label: 'Ingreso',
        title: 'Añadir ingreso',
        description: 'Carga manualmente el dinero que entra a una cuenta.',
        amountLabel: 'Monto',
        selectedColor: 'bg-[#5EF06A]',
    },
    expense: {
        label: 'Gasto',
        title: 'Añadir gasto',
        description: 'Carga manualmente el dinero que sale de una cuenta.',
        amountLabel: 'Monto',
        selectedColor: 'bg-[#FF3744] text-white',
    },
    transfer: {
        label: 'Transferencia',
        title: 'Añadir transferencia',
        description: 'Mueve dinero entre dos cuentas propias.',
        amountLabel: 'Sale',
        selectedColor: 'bg-[#6DE7D8]',
    },
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
    const [isRecurring, setIsRecurring] = useState(false)
    const [recurrenceFrequency, setRecurrenceFrequency] =
        useState<RecurrenceFrequency>('monthly')
    const [recurrenceDayInterval, setRecurrenceDayInterval] = useState(
        DEFAULT_RECURRENCE_DAY_INTERVAL,
    )
    const [recurrenceEndDate, setRecurrenceEndDate] = useState('')

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
    const config = typeConfig[type]

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
            toast.error('Selecciona una cuenta')
            return
        }
        if (!selectedCategory) {
            toast.error('Selecciona una categoria')
            return
        }
        const parsedAmount = parseFormAmount(amount)
        if (!parsedAmount) {
            toast.error('El monto debe ser mayor a 0')
            return
        }

        const trimmedTitle =
            type === 'transfer' ? 'Transferencia' : title.trim()
        if (!trimmedTitle) {
            toast.error('El titulo es obligatorio')
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
                toast.error('Selecciona una cuenta destino')
                return
            }
            if (destinationAccountId === accountId) {
                toast.error('Origen y destino deben ser cuentas distintas')
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
                    toast.error('El monto destino debe ser mayor a 0')
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
            toast.success('Movimiento anotado')
            navigate('/activity')
        } catch (error) {
            toast.error(
                error instanceof Error
                    ? error.message
                    : 'No se pudo anotar el movimiento',
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
            toast.error('Ya existe una cuenta con ese nombre y moneda')
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
            toast.error('Ya existe una categoría con ese nombre')
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
            <div className="flex min-h-full items-center justify-center bg-[#FFF8F8] px-4 py-10">
                <Loader2 className="size-6 animate-spin text-muted-foreground" />
            </div>
        )
    }

    return (
        <div className="flex min-h-full justify-center bg-[#FFF8F8] px-4 py-10">
            <form
                onSubmit={(event) => void submit(event)}
                className="flex w-full max-w-xl flex-col gap-10"
            >
                <header className="space-y-6 text-center">
                    <div className="inline-flex rounded-full border border-[#D9D0D6] bg-white p-1 shadow-sm">
                        {(Object.keys(typeConfig) as MovementType[]).map(
                            (item) => (
                                <button
                                    key={item}
                                    type="button"
                                    onClick={() => changeType(item)}
                                    className={cn(
                                        'rounded-full px-4 py-2 text-sm font-bold text-black transition-colors',
                                        type === item
                                            ? typeConfig[item].selectedColor
                                            : 'hover:bg-[#FFF4F6]',
                                    )}
                                >
                                    {typeConfig[item].label}
                                </button>
                            ),
                        )}
                    </div>

                    <div className="space-y-3">
                        <h1 className="text-3xl font-black tracking-tight text-black">
                            {config.title}
                        </h1>
                        <p className="text-sm text-muted-foreground">
                            {config.description}
                        </p>
                    </div>
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
                        onDestinationAccountChange={updateDestinationAccount}
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
                                        if (amount.trim() === '') setAmount('0')
                                    }}
                                    onChange={(event) =>
                                        setAmount(
                                            normalizeAmountInput(
                                                event.target.value,
                                            ),
                                        )
                                    }
                                    placeholder="0,00"
                                    className="h-16 rounded-xl border-[#D9D0D6] bg-white px-20 text-center text-4xl font-normal text-black shadow-sm"
                                    required
                                />
                                <span className="absolute top-1/2 right-4 -translate-y-1/2 text-sm font-bold text-muted-foreground">
                                    {selectedAccount?.currency}
                                </span>
                            </div>
                        </div>

                        <div className="grid gap-5 sm:grid-cols-2">
                            <Field
                                label="Cuenta"
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
                                            <X className="size-3" />
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
                                            <Plus className="size-3" />
                                            Nueva cuenta
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

                            <Field label="Fecha" htmlFor="date">
                                <DateInput value={date} onChange={setDate} />
                            </Field>

                            <Field label="Hora (opcional)" htmlFor="time">
                                <TimeInput value={time} onChange={setTime} />
                            </Field>
                        </div>

                        <RecurrenceControl
                            label={
                                type === 'income'
                                    ? 'Ingreso recurrente'
                                    : 'Gasto recurrente'
                            }
                            isRecurring={isRecurring}
                            onIsRecurringChange={setIsRecurring}
                            frequency={recurrenceFrequency}
                            onFrequencyChange={setRecurrenceFrequency}
                            dayInterval={recurrenceDayInterval}
                            onDayIntervalChange={setRecurrenceDayInterval}
                            endDate={recurrenceEndDate}
                            onEndDateChange={setRecurrenceEndDate}
                            minEndDate={date}
                            disabled={isSaving}
                        />
                    </section>
                )}

                <section className="space-y-5">
                    <Field label="Título" htmlFor="title">
                        <Input
                            id="title"
                            value={title}
                            onChange={(event) => setTitle(event.target.value)}
                            placeholder={
                                type === 'transfer'
                                    ? 'Transferencia a ahorro'
                                    : type === 'income'
                                      ? 'Salario, devolución, intereses'
                                      : 'Supermercado, taxi, alquiler'
                            }
                            className="h-11 rounded-xl border-[#D9D0D6] bg-white"
                            required={type !== 'transfer'}
                        />
                    </Field>

                    <Field label="Descripción" htmlFor="description">
                        <Textarea
                            id="description"
                            value={description}
                            onChange={(event) =>
                                setDescription(event.target.value)
                            }
                            placeholder="Detalle opcional"
                            rows={3}
                            className="rounded-xl border-[#D9D0D6] bg-white"
                        />
                    </Field>

                    <Field
                        label="Categoría"
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
                                    <X className="size-3" />
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
                                    <Plus className="size-3" />
                                    Nueva categoría
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
                            className="h-11 w-full rounded-xl border border-[#D9D0D6] bg-white px-3 text-sm outline-none focus-visible:border-[#21C4B6] focus-visible:ring-3 focus-visible:ring-[#21C4B6]/30"
                            required
                        >
                            <option value="">Sin seleccionar</option>
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
                    <div className="rounded-xl border border-[#21C4B6]/30 bg-[#21C4B6]/10 px-4 py-3 text-sm font-medium text-[#11796F]">
                        Movimiento guardado.
                    </div>
                ) : null}

                <footer className="flex gap-3 pt-2">
                    <Button
                        type="button"
                        variant="outline"
                        className="h-12 flex-1 rounded-xl border-[#F0C9CE] bg-[#F0C9CE] text-black hover:bg-[#E9B9C0]"
                        onClick={() => resetFields()}
                        disabled={isSaving}
                    >
                        <X className="size-4" />
                        Cancelar
                    </Button>
                    <Button
                        type="submit"
                        className="h-12 flex-1 rounded-xl bg-[#21C4B6] text-white hover:bg-[#1BAEA2]"
                        disabled={isSaving}
                    >
                        {isSaving ? (
                            <Loader2 className="size-4 animate-spin" />
                        ) : (
                            <Check className="size-4" />
                        )}
                        Anotar
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
                    label="Sale"
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
                        aria-label="Invertir origen y destino"
                        className="size-11 rounded-full border-[#D9D0D6] bg-[#E7FFFA] p-0 text-black hover:bg-[#CFFFF7]"
                    >
                        <Repeat2 className="size-5" />
                    </Button>
                </div>
                <TransferSide
                    accounts={accounts}
                    label="Entra"
                    amount={destinationAmount}
                    accountId={destinationAccountId}
                    currency={destinationAccount?.currency}
                    onAmountChange={onDestinationAmountChange}
                    onAccountChange={onDestinationAccountChange}
                />
            </div>

            <div className="grid gap-5 sm:grid-cols-2">
                <Field label="Fecha" htmlFor="date">
                    <DateInput value={date} onChange={onDateChange} />
                </Field>
                <Field label="Hora (opcional)" htmlFor="time">
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
            <Label className="block text-base font-black text-black">
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
                    className="h-13 rounded-xl border-[#D9D0D6] bg-white px-14 text-center text-2xl font-normal text-black shadow-sm"
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
    return (
        <section className="space-y-4">
            <Field label="Etiquetas" htmlFor="tags">
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
                        placeholder="Agregar etiqueta"
                        className="h-11 rounded-xl border-[#D9D0D6] bg-white"
                    />
                    <Button
                        type="button"
                        variant="outline"
                        onClick={() => onAddTag(tagInput)}
                        className="h-11 rounded-xl border-[#D9D0D6] bg-white"
                    >
                        <Plus className="size-4" />
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
                            className="h-7 gap-1 rounded-full text-black"
                            style={{ backgroundColor: tag.color }}
                        >
                            {tag.name}
                            <button
                                type="button"
                                onClick={() => onRemoveTag(tag.name)}
                            >
                                <X className="size-3" />
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
                        <DialogTitle>Color de "{tagName}"</DialogTitle>
                    </DialogHeader>
                    <div className="flex flex-wrap gap-3 py-2">
                        {TAG_COLOR_OPTIONS.map((color) => (
                            <button
                                key={color}
                                type="button"
                                aria-label={`Elegir ${color}`}
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
                                    <Check className="size-5 text-black" />
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
                            Cancelar
                        </Button>
                        <Button
                            type="submit"
                            className="bg-[#21C4B6] text-white hover:bg-[#1BAEA2]"
                            autoFocus
                        >
                            Crear
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
    return (
        <select
            id={id}
            value={value}
            onChange={(event) => onChange(event.target.value)}
            className="h-11 w-full rounded-xl border border-[#D9D0D6] bg-white px-3 text-sm outline-none focus-visible:border-[#21C4B6] focus-visible:ring-3 focus-visible:ring-[#21C4B6]/30"
        >
            <option value="">Sin seleccionar</option>
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
            className="h-11 rounded-xl border-[#D9D0D6] bg-white"
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
    return (
        <div className="flex gap-2">
            <Input
                id="time"
                type="time"
                value={value}
                onChange={(event) => onChange(event.target.value)}
                className="h-11 rounded-xl border-[#D9D0D6] bg-white"
            />
            {value ? (
                <Button
                    type="button"
                    variant="outline"
                    size="icon"
                    className="h-11 w-11 shrink-0 rounded-xl border-[#D9D0D6] bg-white"
                    onClick={() => onChange('')}
                    aria-label="Quitar hora"
                >
                    <X className="size-4" />
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
                    className="text-base font-bold text-black"
                >
                    {label}
                </Label>
                {action}
            </div>
            {children}
        </div>
    )
}

function RecurrenceControl({
    label,
    isRecurring,
    onIsRecurringChange,
    frequency,
    onFrequencyChange,
    dayInterval,
    onDayIntervalChange,
    endDate,
    onEndDateChange,
    minEndDate,
    disabled,
}: {
    label: string
    isRecurring: boolean
    onIsRecurringChange: (value: boolean) => void
    frequency: RecurrenceFrequency
    onFrequencyChange: (value: RecurrenceFrequency) => void
    dayInterval: number
    onDayIntervalChange: (value: number) => void
    endDate: string
    onEndDateChange: (value: string) => void
    minEndDate: string
    disabled: boolean
}) {
    return (
        <div className="space-y-4 rounded-xl border border-[#D9D0D6] bg-white p-4 shadow-sm">
            <div className="flex items-center justify-between gap-3">
                <Label
                    htmlFor="recurring"
                    className="text-base font-bold text-black"
                >
                    {label}
                </Label>
                <Switch
                    id="recurring"
                    checked={isRecurring}
                    onCheckedChange={onIsRecurringChange}
                    disabled={disabled}
                />
            </div>

            {isRecurring ? (
                <div className="space-y-4 rounded-lg border border-[#21C4B6] bg-[#F3FBFA] p-4">
                    <div className="space-y-2">
                        <Label className="text-sm font-bold text-black">
                            Frecuencia
                        </Label>
                        <div className="flex flex-wrap gap-2">
                            {RECURRENCE_FREQUENCY_OPTIONS.map((option) => (
                                <button
                                    key={option.value}
                                    type="button"
                                    disabled={disabled}
                                    onClick={() =>
                                        onFrequencyChange(option.value)
                                    }
                                    className={cn(
                                        'rounded-full border px-4 py-1.5 text-sm font-medium transition-colors disabled:opacity-50',
                                        frequency === option.value
                                            ? 'border-[#21C4B6] bg-[#21C4B6] text-white'
                                            : 'border-[#D9D0D6] bg-white text-black hover:bg-[#E7FFFA]',
                                    )}
                                >
                                    {option.label}
                                </button>
                            ))}
                        </div>
                    </div>

                    {frequency === 'customDays' ? (
                        <div className="flex items-center gap-3">
                            <Label
                                htmlFor="recurrence-day-interval"
                                className="text-sm font-bold text-black"
                            >
                                Repetir cada
                            </Label>
                            <Input
                                id="recurrence-day-interval"
                                type="number"
                                min={1}
                                value={dayInterval}
                                onChange={(event) => {
                                    const parsed = Number.parseInt(
                                        event.target.value,
                                        10,
                                    )
                                    if (Number.isNaN(parsed) || parsed < 1) {
                                        return
                                    }
                                    onDayIntervalChange(parsed)
                                }}
                                disabled={disabled}
                                className="h-11 w-20 rounded-xl border-[#D9D0D6] bg-white text-center"
                            />
                            <span className="text-sm font-medium text-black">
                                días
                            </span>
                        </div>
                    ) : null}

                    <Field
                        label="Fecha de fin (opcional)"
                        htmlFor="recurrence-end-date"
                        action={
                            endDate ? (
                                <Button
                                    type="button"
                                    variant="outline"
                                    size="sm"
                                    className="h-8 rounded-full"
                                    onClick={() => onEndDateChange('')}
                                    disabled={disabled}
                                >
                                    <X className="size-3" />
                                </Button>
                            ) : undefined
                        }
                    >
                        <Input
                            id="recurrence-end-date"
                            type="date"
                            value={endDate}
                            min={minEndDate}
                            onChange={(event) =>
                                onEndDateChange(event.target.value)
                            }
                            disabled={disabled}
                            className="h-11 rounded-xl border-[#D9D0D6] bg-white"
                        />
                    </Field>
                </div>
            ) : null}
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
        toast.success('Cuenta agregada al formulario')
    }

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>Nueva cuenta</DialogTitle>
                </DialogHeader>
                <form
                    className="space-y-4"
                    onSubmit={(event) => {
                        event.preventDefault()
                        handleCreate()
                    }}
                >
                    <Field label="Nombre" htmlFor="mock-account-name">
                        <Input
                            id="mock-account-name"
                            value={name}
                            onChange={(event) => setName(event.target.value)}
                            placeholder="Ej: Efectivo, Banco Nación"
                        />
                    </Field>
                    <Field label="Moneda" htmlFor="mock-account-currency">
                        <select
                            id="mock-account-currency"
                            value={currency}
                            onChange={(event) =>
                                setCurrency(
                                    event.target
                                        .value as (typeof MOCK_CURRENCIES)[number],
                                )
                            }
                            className="h-11 w-full rounded-xl border border-[#D9D0D6] bg-white px-3 text-sm outline-none focus-visible:border-[#21C4B6] focus-visible:ring-3 focus-visible:ring-[#21C4B6]/30"
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
                        Cancelar
                    </Button>
                    <Button
                        type="button"
                        onClick={() => void handleCreate()}
                        disabled={isSubmitting}
                    >
                        Crear
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
        toast.success('Categoría agregada al formulario')
    }

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>Nueva categoría</DialogTitle>
                </DialogHeader>
                <form
                    onSubmit={(event) => {
                        event.preventDefault()
                        handleCreate()
                    }}
                >
                    <Field label="Nombre" htmlFor="mock-category-name">
                        <Input
                            id="mock-category-name"
                            value={name}
                            onChange={(event) => setName(event.target.value)}
                            placeholder="Ej: Comida, Regalo, Freelance"
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
                        Cancelar
                    </Button>
                    <Button
                        type="button"
                        onClick={() => void handleCreate()}
                        disabled={isSubmitting}
                    >
                        Crear
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    )
}
