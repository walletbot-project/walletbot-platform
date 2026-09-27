import { BottomSheet } from '@/components/m3/bottom-sheet'
import { Icon } from '@/components/m3/icon'
import { useWindowSizeClass } from '@/hooks/use-window-size-class'
import { useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'

/**
 * The "what do you want to record?" step an entity detail shows before the
 * manual form. Its own list rather than `OptionSheet`: as a dialog the framing
 * already adds its vertical inset, so only the sheet keeps extra room below
 * the last row.
 */
export function TransactionTypeSheet({
    open,
    onOpenChange,
    onSelect,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    onSelect: (type: 'income' | 'expense') => void
}) {
    const t = useT()
    const asDialog = useWindowSizeClass() !== 'compact'
    const choices: {
        type: 'income' | 'expense'
        icon: string
        label: string
    }[] = [
        { type: 'income', icon: 'add', label: t.addManual.incomeLabel },
        { type: 'expense', icon: 'remove', label: t.addManual.expenseLabel },
    ]
    return (
        <BottomSheet
            open={open}
            onOpenChange={onOpenChange}
            title={t.addManual.chooseType}
            showTitle
        >
            <ul className={cn('flex flex-col px-4', !asDialog && 'pb-6')}>
                {choices.map((choice) => (
                    <li key={choice.type}>
                        <button
                            type="button"
                            onClick={() => onSelect(choice.type)}
                            className="m3-state-layer flex w-full cursor-pointer items-center gap-4 rounded-2xl px-3 py-3 text-left text-on-surface"
                        >
                            <Icon name={choice.icon} />
                            <span className="m3-body-large">
                                {choice.label}
                            </span>
                        </button>
                    </li>
                ))}
            </ul>
        </BottomSheet>
    )
}
