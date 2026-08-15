import { Button, CircularProgress, TextField } from 'actify'
import { type FormEvent, useMemo, useState } from 'react'
import { ColorSwatches } from '@/components/color-swatches'
import { IconPicker } from '@/components/icon-picker'
import { ChoiceChip } from '@/components/m3/chip'
import { FormScreen } from '@/components/m3/form-screen'
import { Icon } from '@/components/m3/icon'
import { OptionSheet, type SheetOption } from '@/components/m3/option-sheet'
import { PickerField } from '@/components/m3/picker-field'
import {
    ACCOUNT_DEFAULT_ICON,
    ACCOUNT_ICONS,
    accountIcon,
} from '@/lib/account-icons'
import {
    CURRENCY_CODES,
    currencyName,
    DEFAULT_CURRENCY,
    SUGGESTED_CURRENCIES,
} from '@/lib/currencies'
import { ACCOUNT_DEFAULT_COLOR, COLOR_OPTIONS } from '@/lib/entity-colors'
import { type Messages, useFormatLocale, useT } from '@/lib/i18n'

export type AccountFormValue = {
    name: string
    currency: string
    color: string
    icon: string
    /** Initial balance in cents, or null when left empty. */
    initialBalanceCents: number | null
}

/**
 * The name shortcuts the native form offers above the name field — tapping one
 * fills the name and switches the icon to match (`_nameSuggestions`).
 */
const NAME_SUGGESTIONS: { label: (t: Messages) => string; icon: string }[] = [
    { label: (t) => t.accounts.suggestionCash, icon: 'cash' },
    { label: (t) => t.accounts.suggestionBank, icon: 'bank' },
    { label: (t) => t.accounts.suggestionCard, icon: 'card' },
]

/**
 * Account creation, porting `CreateAccountScreen`. Rendered in the divided
 * view's pane on expanded windows and over the window on smaller ones — the
 * same node either way.
 */
export function AccountForm({
    onClose,
    onSubmit,
}: {
    onClose: () => void
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
    const [currencyOpen, setCurrencyOpen] = useState(false)

    const currencyOptions: SheetOption[] = useMemo(
        () =>
            CURRENCY_CODES.map((code) => ({
                id: code,
                label: code,
                supporting: currencyName(code, formatLocale),
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

    const handleSubmit = async (event: FormEvent) => {
        event.preventDefault()
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
        <FormScreen title={t.accounts.newAccount} onClose={onClose}>
            <form onSubmit={handleSubmit} className="flex flex-col gap-6 p-4">
                <section className="flex flex-col gap-2">
                    <h2 className="m3-label-large text-on-surface">
                        {t.accounts.suggestions}
                    </h2>
                    <div className="flex flex-wrap gap-2">
                        {NAME_SUGGESTIONS.map((suggestion) => {
                            const label = suggestion.label(t)
                            const option = accountIcon(suggestion.icon)
                            return (
                                <ChoiceChip
                                    key={suggestion.icon}
                                    label={label}
                                    selected={false}
                                    onSelect={() => {
                                        setName(label)
                                        setIcon(suggestion.icon)
                                    }}
                                    leading={
                                        <Icon
                                            name={option.symbol}
                                            filled={option.filled}
                                            size={18}
                                        />
                                    }
                                />
                            )
                        })}
                    </div>
                </section>

                <TextField
                    variant="outlined"
                    className="w-full"
                    label={t.common.name}
                    value={name}
                    onChange={setName}
                    placeholder={t.accounts.namePlaceholder}
                    isRequired
                    isDisabled={submitting}
                    autoFocus
                />

                <section className="flex flex-col gap-3">
                    <h2 className="m3-label-large text-on-surface">
                        {t.common.iconAndColor}
                    </h2>
                    <div className="flex items-start gap-4">
                        <IconPicker
                            icon={icon}
                            color={color}
                            onIconChange={setIcon}
                            icons={ACCOUNT_ICONS}
                        />
                        <div className="flex-1">
                            <ColorSwatches
                                value={color}
                                onChange={setColor}
                                options={COLOR_OPTIONS}
                            />
                        </div>
                    </div>
                </section>

                <PickerField
                    label={t.common.currency}
                    value={currency}
                    onClick={() => setCurrencyOpen(true)}
                    disabled={submitting}
                />

                <div className="flex flex-col gap-1">
                    <TextField
                        variant="outlined"
                        className="w-full"
                        label={t.accounts.initialBalance}
                        value={balance}
                        onChange={setBalance}
                        placeholder="0.00"
                        prefixText={`${currency} `}
                        inputMode="decimal"
                        isDisabled={submitting}
                    />
                    {balanceError ? (
                        <p className="m3-body-small px-4 text-error">
                            {balanceError}
                        </p>
                    ) : null}
                </div>

                <Button
                    type="submit"
                    variant="filled"
                    className="w-full"
                    isDisabled={
                        submitting || !name.trim() || balanceError !== null
                    }
                >
                    {submitting ? (
                        <CircularProgress isIndeterminate size="xs" />
                    ) : null}
                    {t.accounts.createAccount}
                </Button>
            </form>

            <OptionSheet
                open={currencyOpen}
                onOpenChange={setCurrencyOpen}
                title={t.accounts.chooseCurrency}
                options={currencyOptions}
                selected={currency}
                onSelect={(code) => {
                    setCurrency(code)
                    setCurrencyOpen(false)
                }}
                searchPlaceholder={t.accounts.searchCurrency}
                suggested={SUGGESTED_CURRENCIES}
            />
        </FormScreen>
    )
}
