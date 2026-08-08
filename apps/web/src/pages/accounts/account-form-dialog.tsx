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
import {
    CURRENCY_CODES,
    currencyName,
    DEFAULT_CURRENCY,
} from '@/lib/currencies'
import { ACCOUNT_DEFAULT_COLOR, COLOR_OPTIONS } from '@/lib/entity-colors'
import { useFormatLocale, useT } from '@/lib/i18n'

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
    const t = useT()
    const formatLocale = useFormatLocale()
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
            CURRENCY_CODES.map((code) => ({
                value: code,
                label: `${code} — ${currencyName(code, formatLocale)}`,
            })),
        [formatLocale],
    )

    const balanceError = useMemo(() => {
        const trimmed = balance.trim()
        if (!trimmed) return null
        const parsed = Number.parseFloat(trimmed.replace(',', '.'))
        if (Number.isNaN(parsed) || parsed < 0) return t.accounts.invalidAmount
        return null
    }, [balance, t])

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
                    <DialogTitle>{t.accounts.newAccount}</DialogTitle>
                </DialogHeader>
                <form onSubmit={handleSubmit} className="flex flex-col gap-4">
                    <div className="flex flex-col gap-2">
                        <Label htmlFor="account-name">{t.common.name}</Label>
                        <Input
                            id="account-name"
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            placeholder={t.accounts.namePlaceholder}
                            autoFocus
                            required
                        />
                    </div>

                    <div className="flex flex-col gap-2">
                        <Label>{t.common.iconAndColor}</Label>
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
                        <Label>{t.common.currency}</Label>
                        <Combobox
                            value={[currency]}
                            onChange={(values) =>
                                setCurrency(values[0] ?? DEFAULT_CURRENCY)
                            }
                            options={currencyOptions}
                            placeholder={t.accounts.chooseCurrency}
                            searchPlaceholder={t.accounts.searchCurrency}
                            emptyMessage={t.common.noResults}
                            className="w-full"
                        />
                    </div>

                    <div className="flex flex-col gap-2">
                        <Label htmlFor="account-balance">
                            {t.accounts.initialBalance}
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
                            {t.common.cancel}
                        </Button>
                        <Button
                            type="submit"
                            disabled={
                                submitting ||
                                !name.trim() ||
                                balanceError !== null
                            }
                        >
                            {t.accounts.createAccount}
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    )
}
