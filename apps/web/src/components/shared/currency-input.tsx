import { useCallback, useState } from 'react'
import { Input } from '@/components/ui/input'
import { cn } from '@/lib/utils'

interface CurrencyInputProps {
    value: number | undefined
    onChange: (cents: number) => void
    currency: string
    placeholder?: string
    className?: string
    disabled?: boolean
}

const SYMBOLS: Record<string, string> = {
    USD: '$',
    ARS: 'AR$',
    EUR: '\u20AC',
    BRL: 'R$',
}

export function CurrencyInput({
    value,
    onChange,
    currency,
    placeholder = '0.00',
    className,
    disabled,
}: CurrencyInputProps) {
    const [displayValue, setDisplayValue] = useState(() =>
        value !== undefined ? (value / 100).toFixed(2) : '',
    )

    const handleChange = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            const raw = e.target.value
            setDisplayValue(raw)
            const parsed = parseFloat(raw)
            if (!Number.isNaN(parsed) && parsed >= 0) {
                onChange(Math.round(parsed * 100))
            }
        },
        [onChange],
    )

    const symbol = SYMBOLS[currency] ?? currency

    return (
        <div className={cn('relative', className)}>
            <span className="absolute left-2.5 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">
                {symbol}
            </span>
            <Input
                type="number"
                step="0.01"
                min="0.01"
                placeholder={placeholder}
                value={displayValue}
                onChange={handleChange}
                disabled={disabled}
                className="pl-10"
            />
        </div>
    )
}
