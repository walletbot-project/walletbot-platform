import { type TranslationKey, t } from '@wallet-bot/shared'
import { CurrencyDisplay } from '@/components/shared/currency-display'
import { Badge } from '@/components/ui/badge'
import { useCategories } from '@/hooks/use-categories'
import { formatDateRelative, TX_TYPE_ICONS, txTypeColor } from '@/lib/format'
import { cn } from '@/lib/utils'
import type { Transaction } from './types'

interface TransactionListItemProps {
    transaction: Transaction
    onClick: () => void
}

export function TransactionListItem({
    transaction: tx,
    onClick,
}: TransactionListItemProps) {
    const { flatCategories } = useCategories()
    const Icon = TX_TYPE_ICONS[tx.type]

    const cat = tx.categoryId
        ? flatCategories.find((c) => c._id === tx.categoryId)
        : null
    const catName = cat
        ? cat.isSystem
            ? t(cat.name as TranslationKey)
            : cat.name
        : null

    return (
        <button
            type="button"
            onClick={onClick}
            className="flex w-full items-center gap-3 rounded-lg border p-3 text-left transition-colors hover:bg-muted/50"
        >
            <div
                className={cn(
                    'flex size-8 shrink-0 items-center justify-center rounded-full',
                    tx.type === 'expense'
                        ? 'bg-red-100 dark:bg-red-900/30'
                        : tx.type === 'income'
                          ? 'bg-green-100 dark:bg-green-900/30'
                          : 'bg-blue-100 dark:bg-blue-900/30',
                )}
            >
                <Icon className={cn('size-4', txTypeColor(tx.type))} />
            </div>
            <div className="flex-1 overflow-hidden">
                <div className="flex items-center gap-2">
                    <span className="truncate text-sm font-medium">
                        {tx.description}
                    </span>
                    {catName && (
                        <Badge
                            variant="secondary"
                            className="shrink-0 text-[10px]"
                        >
                            {catName}
                        </Badge>
                    )}
                </div>
                <span className="text-xs text-muted-foreground">
                    {formatDateRelative(tx.date)}
                </span>
            </div>
            <CurrencyDisplay
                cents={tx.amount}
                currency={tx.currency}
                className={cn(
                    'shrink-0 text-sm font-semibold',
                    txTypeColor(tx.type),
                )}
            />
        </button>
    )
}
