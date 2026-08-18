import { TextField } from 'actify'
import { type FormEvent, useMemo, useState } from 'react'
import {
    FormSubmitButton,
    IconColorSection,
    NameSuggestions,
} from '@/components/entity-form-sections'
import { FormScreen } from '@/components/m3/form-screen'
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
import { ACCOUNT_DEFAULT_COLOR } from '@/lib/entity-colors'
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
                <NameSuggestions
                    suggestions={NAME_SUGGESTIONS.map((suggestion) => ({
                        label: suggestion.label(t),
                        icon: suggestion.icon,
                    }))}
                    resolveIcon={accountIcon}
                    onPick={(suggestion) => {
                        setName(suggestion.label)
                        setIcon(suggestion.icon)
                    }}
                />

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

                <IconColorSection
                    icon={icon}
                    color={color}
                    onIconChange={setIcon}
                    onColorChange={setColor}
                    icons={ACCOUNT_ICONS}
                />

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

                <FormSubmitButton
                    submitting={submitting}
                    isDisabled={
                        submitting || !name.trim() || balanceError !== null
                    }
                    label={t.accounts.createAccount}
                />
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
