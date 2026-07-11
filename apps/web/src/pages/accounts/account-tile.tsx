import { api } from '@wallet-bot/backend/api'
import { useQuery } from 'convex/react'
import { AccountIcon } from '@/components/account-icon'
import { ACCOUNT_DEFAULT_COLOR, normalizeColor } from '@/lib/entity-colors'
import { formatMoney } from '@/lib/money'
import { cn } from '@/lib/utils'

type AccountTileProps = {
    id: string
    name: string
    icon?: string
    color?: string
    onClick: () => void
}

/** One account row: tinted icon avatar, name, and a live balance (red if negative). */
export function AccountTile({
    id,
    name,
    icon,
    color,
    onClick,
}: AccountTileProps) {
    const balance = useQuery(api.v1.transactions.queries.balance, {
        accountId: id,
    })
    const accent = normalizeColor(color, ACCOUNT_DEFAULT_COLOR)

    const cents = balance ? Number(balance.balance) : null
    const isNegative = cents !== null && cents < 0

    return (
        <button
            type="button"
            onClick={onClick}
            className="flex w-full items-center gap-4 px-4 py-3 text-left transition-colors hover:bg-accent/50"
        >
            <span
                className="flex size-10 shrink-0 items-center justify-center rounded-full"
                style={{ backgroundColor: `${accent}2E` }}
            >
                <AccountIcon name={icon} className="size-5" color={accent} />
            </span>
            <span className="min-w-0 flex-1 truncate text-sm">{name}</span>
            <span
                className={cn(
                    'shrink-0 text-sm font-semibold tabular-nums',
                    isNegative ? 'text-destructive' : 'text-foreground',
                )}
            >
                {balance
                    ? formatMoney(Number(balance.balance), balance.currency)
                    : '—'}
            </span>
        </button>
    )
}
