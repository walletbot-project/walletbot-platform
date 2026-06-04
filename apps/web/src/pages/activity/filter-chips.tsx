import { Button } from '@/components/ui/button'
import type { TransactionType } from './helpers'

const OPTIONS: { value: TransactionType | null; label: string }[] = [
    { value: null, label: 'Todos' },
    { value: 'income', label: 'Ingresos' },
    { value: 'expense', label: 'Gastos' },
    { value: 'transfer', label: 'Transferencias' },
    { value: 'balance_adjustment', label: 'Ajustes' },
]

type FilterChipsProps = {
    selected: TransactionType | null
    onChange: (value: TransactionType | null) => void
}

export function FilterChips({ selected, onChange }: FilterChipsProps) {
    return (
        <div className="flex gap-2 overflow-x-auto pb-1">
            {OPTIONS.map((option) => {
                const isSelected = option.value === selected
                return (
                    <Button
                        key={option.label}
                        type="button"
                        size="sm"
                        variant={isSelected ? 'secondary' : 'outline'}
                        className="shrink-0 rounded-full"
                        onClick={() => onChange(option.value)}
                    >
                        {option.label}
                    </Button>
                )
            })}
        </div>
    )
}
