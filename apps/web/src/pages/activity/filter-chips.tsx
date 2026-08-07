import { Button } from '@/components/ui/button'
import { type Messages, useT } from '@/lib/i18n'
import type { TransactionType } from './helpers'

const OPTIONS: {
    value: TransactionType | null
    label: (t: Messages) => string
}[] = [
    { value: null, label: (t) => t.activity.typeAll },
    { value: 'income', label: (t) => t.activity.typeIncome },
    { value: 'expense', label: (t) => t.activity.typeExpense },
    { value: 'transfer', label: (t) => t.activity.typeTransfer },
    {
        value: 'balance_adjustment',
        label: (t) => t.activity.typeBalanceAdjustment,
    },
]

type FilterChipsProps = {
    selected: TransactionType | null
    onChange: (value: TransactionType | null) => void
}

export function FilterChips({ selected, onChange }: FilterChipsProps) {
    const t = useT()
    return (
        <div className="flex gap-2 overflow-x-auto pb-1">
            {OPTIONS.map((option) => {
                const isSelected = option.value === selected
                return (
                    <Button
                        key={option.value ?? 'all'}
                        type="button"
                        size="sm"
                        variant={isSelected ? 'secondary' : 'outline'}
                        className="shrink-0 rounded-full"
                        onClick={() => onChange(option.value)}
                    >
                        {option.label(t)}
                    </Button>
                )
            })}
        </div>
    )
}
