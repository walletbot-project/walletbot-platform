import { Check, Pencil, Trash2, X } from 'lucide-react'
import { type ReactNode, useId, useState } from 'react'
import { toast } from 'sonner'
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
import {
    Sheet,
    SheetContent,
    SheetFooter,
    SheetHeader,
    SheetTitle,
} from '@/components/ui/sheet'
import { Textarea } from '@/components/ui/textarea'
import { formatMoney } from '@/lib/money'
import {
    FREQUENCY_LABELS,
    type FutureMovement,
    fromDateTimeInputs,
    MOCK_ACCOUNTS,
    MOCK_CATEGORIES,
    type MockFrequency,
    type RecurrenceScope,
    toDateInput,
    toTimeInput,
} from './helpers'

const SELECT_CLASS =
    'h-11 w-full rounded-xl border border-[#D9D0D6] bg-white px-3 text-sm outline-none focus-visible:border-[#21C4B6] focus-visible:ring-3 focus-visible:ring-[#21C4B6]/30'

function signedCents(movement: FutureMovement): number {
    const amount = Number(movement.amount)
    return movement.type === 'expense' ? -Math.abs(amount) : Math.abs(amount)
}

export function FutureMovementDetailsSheet({
    movement,
    open,
    onOpenChange,
    onSave,
    onDelete,
}: {
    movement: FutureMovement | null
    open: boolean
    onOpenChange: (open: boolean) => void
    onSave: (
        id: string,
        patch: Partial<FutureMovement>,
        scope: RecurrenceScope,
    ) => void
    onDelete: (id: string, scope: RecurrenceScope) => void
}) {
    return (
        <Sheet open={open} onOpenChange={onOpenChange}>
            <SheetContent side="right" className="sm:max-w-lg">
                {movement ? (
                    <DetailsContent
                        key={movement.id}
                        movement={movement}
                        onClose={() => onOpenChange(false)}
                        onSave={onSave}
                        onDelete={onDelete}
                    />
                ) : null}
            </SheetContent>
        </Sheet>
    )
}

function DetailsContent({
    movement,
    onClose,
    onSave,
    onDelete,
}: {
    movement: FutureMovement
    onClose: () => void
    onSave: (
        id: string,
        patch: Partial<FutureMovement>,
        scope: RecurrenceScope,
    ) => void
    onDelete: (id: string, scope: RecurrenceScope) => void
}) {
    const formId = useId()
    const [editing, setEditing] = useState(false)
    const [name, setName] = useState(movement.name)
    const [description, setDescription] = useState(movement.description ?? '')
    const [amount, setAmount] = useState(
        Math.round(Math.abs(Number(movement.amount)) / 100).toString(),
    )
    const [date, setDate] = useState(toDateInput(movement.date))
    const [time, setTime] = useState(toTimeInput(movement.date))
    const [accountId, setAccountId] = useState(movement.accountId)
    const [categoryId, setCategoryId] = useState(movement.categoryId)
    const [frequency, setFrequency] = useState<MockFrequency>(
        movement.frequency,
    )
    const [dayInterval, setDayInterval] = useState(movement.dayInterval ?? 15)

    // The scope prompt shown before committing an edit or a delete.
    const [pendingScope, setPendingScope] = useState<'save' | 'delete' | null>(
        null,
    )

    const cents = signedCents(movement)
    const sign = cents < 0 ? '-' : cents > 0 ? '+' : ''

    function buildPatch(): Partial<FutureMovement> | null {
        const trimmedName = name.trim()
        if (!trimmedName) {
            toast.error('El título es obligatorio')
            return null
        }
        const parsedAmount = Number(amount.trim().replace(',', '.'))
        if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
            toast.error('El monto debe ser mayor a 0')
            return null
        }
        return {
            name: trimmedName,
            description: description.trim() ? description.trim() : null,
            amount: BigInt(Math.round(parsedAmount * 100)),
            date: fromDateTimeInputs(date, time),
            accountId,
            categoryId,
            frequency,
            dayInterval:
                frequency === 'customDays'
                    ? Math.max(1, dayInterval)
                    : undefined,
        }
    }

    function handleSaveClick() {
        if (buildPatch() === null) return
        setPendingScope('save')
    }

    function applyScope(scope: RecurrenceScope) {
        if (pendingScope === 'delete') {
            onDelete(movement.id, scope)
            setPendingScope(null)
            onClose()
            return
        }
        const patch = buildPatch()
        if (!patch) {
            setPendingScope(null)
            return
        }
        onSave(movement.id, patch, scope)
        setPendingScope(null)
        setEditing(false)
    }

    return (
        <>
            <SheetHeader className="flex-row items-center border-b">
                <SheetTitle className="flex-1">
                    {editing ? 'Editar movimiento' : 'Detalle'}
                </SheetTitle>
                {editing ? (
                    <span className="size-8 shrink-0" aria-hidden />
                ) : (
                    <Button
                        variant="ghost"
                        size="icon-sm"
                        onClick={() => setEditing(true)}
                        aria-label="Editar"
                    >
                        <Pencil />
                    </Button>
                )}
                <Button
                    variant="ghost"
                    size="icon-sm"
                    onClick={() => setPendingScope('delete')}
                    aria-label="Eliminar"
                >
                    <Trash2 />
                </Button>
                <Button
                    variant="ghost"
                    size="icon-sm"
                    onClick={onClose}
                    aria-label="Cerrar"
                >
                    <X />
                </Button>
            </SheetHeader>

            <form
                id={formId}
                className="flex flex-1 flex-col gap-4 overflow-y-auto p-4"
                onSubmit={(event) => {
                    event.preventDefault()
                    handleSaveClick()
                }}
            >
                <div className="flex items-start justify-between gap-3">
                    {editing ? (
                        <Input
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            className="h-11 flex-1 rounded-xl"
                            placeholder="Título"
                        />
                    ) : (
                        <h2 className="text-xl font-bold text-foreground">
                            {movement.name}
                        </h2>
                    )}
                    {!editing ? (
                        <span
                            className={
                                cents > 0
                                    ? 'text-lg font-semibold text-green-600'
                                    : 'text-lg font-semibold text-foreground'
                            }
                        >
                            {sign
                                ? `${sign} ${formatMoney(Math.abs(cents), movement.currency)}`
                                : formatMoney(cents, movement.currency)}
                        </span>
                    ) : null}
                </div>

                {editing ? (
                    <ReceiptRow label="Monto">
                        <Input
                            inputMode="decimal"
                            value={amount}
                            onChange={(e) => setAmount(e.target.value)}
                            className="h-11 rounded-xl"
                        />
                    </ReceiptRow>
                ) : null}

                <ReceiptRow label="Frecuencia">
                    {editing ? (
                        <div className="flex flex-col gap-2">
                            <select
                                value={frequency}
                                onChange={(e) =>
                                    setFrequency(
                                        e.target.value as MockFrequency,
                                    )
                                }
                                className={SELECT_CLASS}
                            >
                                {(
                                    Object.keys(
                                        FREQUENCY_LABELS,
                                    ) as MockFrequency[]
                                ).map((key) => (
                                    <option key={key} value={key}>
                                        {FREQUENCY_LABELS[key]}
                                    </option>
                                ))}
                            </select>
                            {frequency === 'customDays' ? (
                                <div className="flex items-center gap-2">
                                    <span className="text-sm">
                                        Repetir cada
                                    </span>
                                    <Input
                                        type="number"
                                        min={1}
                                        value={dayInterval}
                                        onChange={(e) => {
                                            const parsed = Number.parseInt(
                                                e.target.value,
                                                10,
                                            )
                                            if (
                                                Number.isNaN(parsed) ||
                                                parsed < 1
                                            )
                                                return
                                            setDayInterval(parsed)
                                        }}
                                        className="h-10 w-20 rounded-xl text-center"
                                    />
                                    <span className="text-sm">días</span>
                                </div>
                            ) : null}
                        </div>
                    ) : (
                        <span>
                            {FREQUENCY_LABELS[movement.frequency]}
                            {movement.frequency === 'customDays' &&
                            movement.dayInterval
                                ? ` (${movement.dayInterval} días)`
                                : ''}
                        </span>
                    )}
                </ReceiptRow>

                <ReceiptRow label="Fecha">
                    {editing ? (
                        <Input
                            type="date"
                            value={date}
                            onChange={(e) => setDate(e.target.value)}
                            className="h-11 rounded-xl"
                        />
                    ) : (
                        <span>{toDateInput(movement.date)}</span>
                    )}
                </ReceiptRow>

                <ReceiptRow label="Hora">
                    {editing ? (
                        <Input
                            type="time"
                            value={time}
                            onChange={(e) => setTime(e.target.value)}
                            className="h-11 rounded-xl"
                        />
                    ) : (
                        <span>{toTimeInput(movement.date)}</span>
                    )}
                </ReceiptRow>

                <ReceiptRow label="Cuenta">
                    {editing ? (
                        <select
                            value={accountId}
                            onChange={(e) => setAccountId(e.target.value)}
                            className={SELECT_CLASS}
                        >
                            {Object.entries(MOCK_ACCOUNTS).map(([id, acc]) => (
                                <option key={id} value={id}>
                                    {acc.name}
                                </option>
                            ))}
                        </select>
                    ) : (
                        <span>
                            {MOCK_ACCOUNTS[movement.accountId]?.name ?? '—'}
                        </span>
                    )}
                </ReceiptRow>

                <ReceiptRow label="Categoría">
                    {editing ? (
                        <select
                            value={categoryId}
                            onChange={(e) => setCategoryId(e.target.value)}
                            className={SELECT_CLASS}
                        >
                            {Object.entries(MOCK_CATEGORIES).map(
                                ([id, cat]) => (
                                    <option key={id} value={id}>
                                        {cat.name}
                                    </option>
                                ),
                            )}
                        </select>
                    ) : (
                        <span>
                            {MOCK_CATEGORIES[movement.categoryId]?.name ?? '—'}
                        </span>
                    )}
                </ReceiptRow>

                <ReceiptRow label="Descripción">
                    {editing ? (
                        <Textarea
                            value={description}
                            onChange={(e) => setDescription(e.target.value)}
                            rows={2}
                            className="rounded-xl"
                            placeholder="Detalle opcional"
                        />
                    ) : (
                        <span className="text-muted-foreground">
                            {movement.description || 'Sin descripción'}
                        </span>
                    )}
                </ReceiptRow>
            </form>

            {editing ? (
                <SheetFooter className="border-t bg-background">
                    <Button type="submit" form={formId} className="w-full">
                        <Check />
                        Guardar cambios
                    </Button>
                </SheetFooter>
            ) : null}

            <ScopeDialog
                open={pendingScope !== null}
                destructive={pendingScope === 'delete'}
                title={
                    pendingScope === 'delete'
                        ? 'Eliminar movimiento recurrente'
                        : 'Guardar cambios'
                }
                description={
                    pendingScope === 'delete'
                        ? `¿Querés eliminar “${movement.name}” solo esta vez o también los futuros?`
                        : '¿Aplicar los cambios solo a este movimiento o también a los futuros?'
                }
                onOpenChange={(next) => {
                    if (!next) setPendingScope(null)
                }}
                onChoose={applyScope}
            />
        </>
    )
}

function ReceiptRow({
    label,
    children,
}: {
    label: string
    children: ReactNode
}) {
    return (
        <div className="flex flex-col gap-1.5">
            <Label className="text-xs font-semibold text-muted-foreground uppercase">
                {label}
            </Label>
            <div className="text-sm text-foreground">{children}</div>
        </div>
    )
}

function ScopeDialog({
    open,
    title,
    description,
    destructive,
    onOpenChange,
    onChoose,
}: {
    open: boolean
    title: string
    description: string
    destructive: boolean
    onOpenChange: (open: boolean) => void
    onChoose: (scope: RecurrenceScope) => void
}) {
    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>{title}</DialogTitle>
                </DialogHeader>
                <p className="text-sm text-muted-foreground">{description}</p>
                <DialogFooter className="flex-col gap-2 sm:flex-col sm:space-x-0">
                    <Button
                        variant={destructive ? 'destructive' : 'default'}
                        className="w-full"
                        onClick={() => onChoose('only-this')}
                    >
                        Solo este movimiento
                    </Button>
                    <Button
                        variant={destructive ? 'destructive' : 'default'}
                        className="w-full"
                        onClick={() => onChoose('all-future')}
                    >
                        Este y los futuros
                    </Button>
                    <Button
                        variant="outline"
                        className="w-full"
                        onClick={() => onOpenChange(false)}
                    >
                        Cancelar
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    )
}
