import { useEffect, useMemo, useState } from 'react'
import { IconColorPicker } from '@/components/icon-color-picker'
import { Button } from '@/components/ui/button'
import { Combobox } from '@/components/ui/combobox'
import {
    Dialog,
    DialogContent,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { ACCOUNT_DEFAULT_ICON, ACCOUNT_ICONS } from '@/lib/account-icons'
import { CURRENCIES, DEFAULT_CURRENCY } from '@/lib/currencies'
import { ACCOUNT_DEFAULT_COLOR, COLOR_OPTIONS } from '@/lib/entity-colors'

export type AccountFormValue = {
    name: string
    currency: string
    color: string
    icon: string
    /** Initial balance in cents, or null when left empty. */
    initialBalanceCents: number | null
}

export function AccountFormDialog({
    open,
    onOpenChange,
    onSubmit,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    onSubmit: (value: AccountFormValue) => Promise<void>
}) {
    const [name, setName] = useState('')
    const [currency, setCurrency] = useState(DEFAULT_CURRENCY)
    const [color, setColor] = useState(ACCOUNT_DEFAULT_COLOR)
    const [icon, setIcon] = useState(ACCOUNT_DEFAULT_ICON)
    const [balance, setBalance] = useState('')
    const [submitting, setSubmitting] = useState(false)

    useEffect(() => {
        if (open) {
            setName('')
            setCurrency(DEFAULT_CURRENCY)
            setColor(ACCOUNT_DEFAULT_COLOR)
            setIcon(ACCOUNT_DEFAULT_ICON)
            setBalance('')
        }
    }, [open])

    const currencyOptions = useMemo(
        () =>
            CURRENCIES.map((c) => ({
                value: c.code,
                label: `${c.code} — ${c.name}`,
            })),
        [],
    )

    const balanceError = useMemo(() => {
        const trimmed = balance.trim()
        if (!trimmed) return null
        const parsed = Number.parseFloat(trimmed.replace(',', '.'))
        if (Number.isNaN(parsed) || parsed < 0) return 'Ingresá un monto válido'
        return null
    }, [balance])

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault()
        const trimmed = name.trim()
        if (!trimmed || balanceError) return

        const rawBalance = balance.trim()
        const initialBalanceCents = rawBalance
            ? Math.round(Number.parseFloat(rawBalance.replace(',', '.')) * 100)
            : null

        setSubmitting(true)
        try {
            await onSubmit({
                name: trimmed,
                currency,
                color,
                icon,
                initialBalanceCents,
            })
        } finally {
            setSubmitting(false)
        }
    }

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>Nueva cuenta</DialogTitle>
                </DialogHeader>
                <form onSubmit={handleSubmit} className="flex flex-col gap-4">
                    <div className="flex flex-col gap-2">
                        <Label htmlFor="account-name">Nombre</Label>
                        <Input
                            id="account-name"
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            placeholder="Ej: Efectivo, Banco Nación…"
                            autoFocus
                            required
                        />
                    </div>

                    <div className="flex flex-col gap-2">
                        <Label>Ícono y color</Label>
                        <IconColorPicker
                            icon={icon}
                            color={color}
                            onIconChange={setIcon}
                            onColorChange={setColor}
                            icons={ACCOUNT_ICONS}
                            colors={COLOR_OPTIONS}
                        />
                    </div>

                    <div className="flex flex-col gap-2">
                        <Label>Moneda</Label>
                        <Combobox
                            value={[currency]}
                            onChange={(values) =>
                                setCurrency(values[0] ?? DEFAULT_CURRENCY)
                            }
                            options={currencyOptions}
                            placeholder="Elegí una moneda"
                            searchPlaceholder="Buscar moneda…"
                            emptyMessage="Sin resultados"
                            className="w-full"
                        />
                    </div>

                    <div className="flex flex-col gap-2">
                        <Label htmlFor="account-balance">
                            Balance inicial (opcional)
                        </Label>
                        <Input
                            id="account-balance"
                            value={balance}
                            onChange={(e) => setBalance(e.target.value)}
                            inputMode="decimal"
                            placeholder="0.00"
                        />
                        {balanceError ? (
                            <p className="text-xs text-destructive">
                                {balanceError}
                            </p>
                        ) : null}
                    </div>

                    <DialogFooter>
                        <Button
                            type="button"
                            variant="outline"
                            onClick={() => onOpenChange(false)}
                            disabled={submitting}
                        >
                            Cancelar
                        </Button>
                        <Button
                            type="submit"
                            disabled={
                                submitting ||
                                !name.trim() ||
                                balanceError !== null
                            }
                        >
                            Crear cuenta
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    )
}
