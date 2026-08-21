import { ChoiceChip } from '@/components/m3/chip'
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

/** The transaction-type choice chips above the activity list. */
export function FilterChips({ selected, onChange }: FilterChipsProps) {
    const t = useT()
    return (
        <div className="flex gap-2 overflow-x-auto px-4 pb-1">
            {OPTIONS.map((option) => (
                <ChoiceChip
                    key={option.value ?? 'all'}
                    label={option.label(t)}
                    selected={option.value === selected}
                    onSelect={() => onChange(option.value)}
                />
            ))}
        </div>
    )
}
