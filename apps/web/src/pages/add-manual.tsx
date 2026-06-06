import { Check, Plus, Repeat2, X } from 'lucide-react'
import { type FormEvent, useState } from 'react'
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
import { cn } from '@/lib/utils'

type MovementType = 'income' | 'expense' | 'transfer'

type FormTag = {
    name: string
    color: string
}

const accounts = [
    { id: 'mercado-pago', name: 'Mercado Pago', currency: 'ARS' },
    { id: 'efectivo', name: 'Efectivo', currency: 'ARS' },
    { id: 'usd', name: 'USD', currency: 'USD' },
]

const categoriesByType: Record<MovementType, string[]> = {
    income: ['Intereses', 'Salario', 'Reembolso', 'Regalo', 'Otros'],
    expense: ['Comida', 'Transporte', 'Entretenimiento', 'Servicios', 'Otros'],
    transfer: ['Transferencia', 'Ahorro', 'Inversión', 'Viaje'],
}

const knownTags: FormTag[] = [
    { name: 'Trabajo', color: '#42A5F5' },
    { name: 'Ahorro', color: '#26A69A' },
    { name: 'Extra', color: '#FFCA28' },
    { name: 'Viaje', color: '#AB47BC' },
]

const tagColorOptions = [
    '#5EF06A',
    '#26A69A',
    '#42A5F5',
    '#FFCA28',
    '#FF7043',
    '#AB47BC',
    '#78909C',
]

const typeConfig: Record<
    MovementType,
    {
        label: string
        title: string
        description: string
        amountLabel: string
        amountColor: string
        selectedColor: string
    }
> = {
    income: {
        label: 'Ingreso',
        title: 'Añadir ingreso',
        description: 'Carga manualmente el dinero que entra a una cuenta.',
        amountLabel: 'Monto',
        amountColor: 'text-[#35D83B]',
        selectedColor: 'bg-[#5EF06A]',
    },
    expense: {
        label: 'Gasto',
        title: 'Añadir gasto',
        description: 'Carga manualmente el dinero que sale de una cuenta.',
        amountLabel: 'Monto',
        amountColor: 'text-[#FF3744]',
        selectedColor: 'bg-[#FF3744] text-white',
    },
    transfer: {
        label: 'Transferencia',
        title: 'Añadir transferencia',
        description: 'Mueve dinero entre dos cuentas propias.',
        amountLabel: 'Sale',
        amountColor: 'text-black',
        selectedColor: 'bg-[#6DE7D8]',
    },
}

function today() {
    return new Date().toISOString().slice(0, 10)
}

function defaultCategory(type: MovementType) {
    return categoriesByType[type][0] ?? ''
}

function defaultDestinationAccount(sourceId: string) {
    return accounts.find((account) => account.id !== sourceId)?.id ?? ''
}

export function AddManual() {
    const [type, setType] = useState<MovementType>('income')
    const [amount, setAmount] = useState('')
    const [destinationAmount, setDestinationAmount] = useState('')
    const [sourceAmountTouched, setSourceAmountTouched] = useState(false)
    const [destinationAmountTouched, setDestinationAmountTouched] =
        useState(false)
    const [title, setTitle] = useState('')
    const [description, setDescription] = useState('')
    const [date, setDate] = useState(today)
    const [accountId, setAccountId] = useState(accounts[0]?.id ?? '')
    const [destinationAccountId, setDestinationAccountId] = useState(
        defaultDestinationAccount(accounts[0]?.id ?? ''),
    )
    const [category, setCategory] = useState(defaultCategory('income'))
    const [tagInput, setTagInput] = useState('')
    const [tags, setTags] = useState<FormTag[]>([])
    const [pendingTagName, setPendingTagName] = useState<string | null>(null)
    const [pendingTagColor, setPendingTagColor] = useState(tagColorOptions[0])
    const [saved, setSaved] = useState(false)

    const selectedAccount = accounts.find((account) => account.id === accountId)
    const config = typeConfig[type]

    const resetFields = (nextType = type) => {
        const sourceId = accounts[0]?.id ?? ''
        setAmount('')
        setDestinationAmount('')
        setSourceAmountTouched(false)
        setDestinationAmountTouched(false)
        setTitle('')
        setDescription('')
        setDate(today())
        setAccountId(sourceId)
        setDestinationAccountId(defaultDestinationAccount(sourceId))
        setCategory(defaultCategory(nextType))
        setTagInput('')
        setTags([])
        setPendingTagName(null)
        setPendingTagColor(tagColorOptions[0])
        setSaved(false)
    }

    const changeType = (nextType: MovementType) => {
        setType(nextType)
        resetFields(nextType)
    }

    const addTag = (raw: string) => {
        const name = raw.trim()
        if (!name) return
        const existing = knownTags.find(
            (tag) => tag.name.toLowerCase() === name.toLowerCase(),
        )
        if (!existing) {
            setPendingTagName(name)
            setPendingTagColor(tagColorOptions[0])
            return
        }

        addResolvedTag(existing)
        setTagInput('')
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

    const createPendingTag = () => {
        if (!pendingTagName) return
        addResolvedTag({ name: pendingTagName, color: pendingTagColor })
        setTagInput('')
        setPendingTagName(null)
    }

    const sameTransferCurrency = () => {
        const source = accounts.find((account) => account.id === accountId)
        const destination = accounts.find(
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
        setAmount(value)
        setSourceAmountTouched(true)
        if (sameTransferCurrency() && !destinationAmountTouched) {
            setDestinationAmount(value)
        }
    }

    const updateDestinationAmount = (value: string) => {
        setDestinationAmount(value)
        setDestinationAmountTouched(true)
        if (sameTransferCurrency() && !sourceAmountTouched) {
            setAmount(value)
        }
    }

    const updateSourceAccount = (value: string) => {
        setAccountId(value)
        const source = accounts.find((account) => account.id === value)
        const destination = accounts.find(
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
        const source = accounts.find((account) => account.id === accountId)
        const destination = accounts.find((account) => account.id === value)
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

    const submit = (event: FormEvent<HTMLFormElement>) => {
        event.preventDefault()
        setSaved(true)
    }

    return (
        <div className="flex min-h-full justify-center bg-[#FFF8F8] px-4 py-10">
            <form
                onSubmit={submit}
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
                                    onChange={(event) =>
                                        setAmount(event.target.value)
                                    }
                                    placeholder="0,00"
                                    className={cn(
                                        'h-16 rounded-xl border-[#D9D0D6] bg-white pr-20 text-center text-4xl font-black shadow-sm',
                                        config.amountColor,
                                    )}
                                    required
                                />
                                <span className="absolute top-1/2 right-4 -translate-y-1/2 text-sm font-bold text-muted-foreground">
                                    {selectedAccount?.currency}
                                </span>
                            </div>
                        </div>

                        <div className="grid gap-5 sm:grid-cols-2">
                            <Field label="Cuenta" htmlFor="account">
                                <AccountSelect
                                    id="account"
                                    value={accountId}
                                    onChange={setAccountId}
                                />
                            </Field>

                            <Field label="Fecha" htmlFor="date">
                                <DateInput value={date} onChange={setDate} />
                            </Field>
                        </div>
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
                            required
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

                    <Field label="Categoría" htmlFor="category">
                        <select
                            id="category"
                            value={category}
                            onChange={(event) => setCategory(event.target.value)}
                            className="h-11 w-full rounded-xl border border-[#D9D0D6] bg-white px-3 text-sm outline-none focus-visible:border-[#21C4B6] focus-visible:ring-3 focus-visible:ring-[#21C4B6]/30"
                        >
                            {categoriesByType[type].map((item) => (
                                <option key={item} value={item}>
                                    {item}
                                </option>
                            ))}
                        </select>
                    </Field>
                </section>

                <TagsField
                    tags={tags}
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
                        Movimiento listo para guardar.
                    </div>
                ) : null}

                <footer className="flex gap-3 pt-2">
                    <Button
                        type="button"
                        variant="outline"
                        className="h-12 flex-1 rounded-xl border-[#F0C9CE] bg-[#F0C9CE] text-black hover:bg-[#E9B9C0]"
                        onClick={() => resetFields()}
                    >
                        <X className="size-4" />
                        Cancelar
                    </Button>
                    <Button
                        type="submit"
                        className="h-12 flex-1 rounded-xl bg-[#21C4B6] text-white hover:bg-[#1BAEA2]"
                    >
                        <Check className="size-4" />
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
        </div>
    )
}

function TransferAmounts({
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
}: {
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
                    label="Entra"
                    amount={destinationAmount}
                    accountId={destinationAccountId}
                    currency={destinationAccount?.currency}
                    onAmountChange={onDestinationAmountChange}
                    onAccountChange={onDestinationAccountChange}
                />
            </div>

            <Field label="Fecha" htmlFor="date">
                <DateInput value={date} onChange={onDateChange} />
            </Field>
        </section>
    )
}

function TransferSide({
    label,
    amount,
    accountId,
    currency,
    onAmountChange,
    onAccountChange,
}: {
    label: string
    amount: string
    accountId: string
    currency?: string
    onAmountChange: (value: string) => void
    onAccountChange: (value: string) => void
}) {
    return (
        <div className="space-y-3">
            <Label className="block text-center text-base font-black text-black">
                {label}
            </Label>
            <div className="relative">
                <Input
                    inputMode="decimal"
                    value={amount}
                    onChange={(event) => onAmountChange(event.target.value)}
                    placeholder="0,00"
                    className="h-13 rounded-xl border-[#D9D0D6] bg-white pr-14 text-center text-2xl font-black text-black shadow-sm"
                    required
                />
                <span className="absolute top-1/2 right-3 -translate-y-1/2 text-xs font-bold text-muted-foreground">
                    {currency}
                </span>
            </div>
            <AccountSelect value={accountId} onChange={onAccountChange} />
        </div>
    )
}

function TagsField({
    tags,
    tagInput,
    onTagInputChange,
    onAddTag,
    onRemoveTag,
}: {
    tags: FormTag[]
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
                        onChange={(event) => onTagInputChange(event.target.value)}
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
                {knownTags.map((tag) => (
                    <button
                        key={tag.name}
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
                            key={tag.name}
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
    onCreate: () => void
}) {
    return (
        <Dialog open={tagName !== null} onOpenChange={(open) => !open && onCancel()}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>Color de "{tagName}"</DialogTitle>
                </DialogHeader>
                <div className="flex flex-wrap gap-3 py-2">
                    {tagColorOptions.map((color) => (
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
                    <Button type="button" variant="outline" onClick={onCancel}>
                        Cancelar
                    </Button>
                    <Button
                        type="button"
                        className="bg-[#21C4B6] text-white hover:bg-[#1BAEA2]"
                        onClick={onCreate}
                    >
                        Crear
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    )
}

function AccountSelect({
    id,
    value,
    onChange,
}: {
    id?: string
    value: string
    onChange: (value: string) => void
}) {
    return (
        <select
            id={id}
            value={value}
            onChange={(event) => onChange(event.target.value)}
            className="h-11 w-full rounded-xl border border-[#D9D0D6] bg-white px-3 text-sm outline-none focus-visible:border-[#21C4B6] focus-visible:ring-3 focus-visible:ring-[#21C4B6]/30"
        >
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

function Field({
    label,
    htmlFor,
    children,
}: {
    label: string
    htmlFor?: string
    children: React.ReactNode
}) {
    return (
        <div className="space-y-2">
            <Label htmlFor={htmlFor} className="text-base font-bold text-black">
                {label}
            </Label>
            {children}
        </div>
    )
}
