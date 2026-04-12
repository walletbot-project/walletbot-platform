import { Combobox } from '@/components/ui/combobox'

const CURRENCIES = [
    { value: 'USD', label: 'USD ($)' },
    { value: 'ARS', label: 'ARS (AR$)' },
    { value: 'EUR', label: 'EUR (\u20AC)' },
    { value: 'BRL', label: 'BRL (R$)' },
]

interface CurrencySelectorProps {
    value: string
    onChange: (currency: string) => void
    disabled?: boolean
    className?: string
}

export function CurrencySelector({
    value,
    onChange,
    disabled,
    className,
}: CurrencySelectorProps) {
    return (
        <Combobox
            value={[value]}
            onChange={(values) => {
                if (values[0]) onChange(values[0])
            }}
            options={CURRENCIES}
            placeholder="Currency..."
            disabled={disabled}
            className={className}
        />
    )
}
