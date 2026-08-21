import { api } from '@wallet-bot/backend/api'
import { useQuery } from 'convex/react'
import type { CSSProperties } from 'react'
import { AccountIcon } from '@/components/account-icon'
import { EntityAvatar, EntityListTile } from '@/components/m3/entity-list-tile'
import { ACCOUNT_DEFAULT_COLOR, normalizeColor } from '@/lib/entity-colors'
import { useFormatLocale } from '@/lib/i18n'
import { formatMoney } from '@/lib/money'
import { cn } from '@/lib/utils'

type AccountTileProps = {
    id: string
    name: string
    icon?: string
    color?: string
    /** Shape for this tile's position in the group — see `groupedRadius`. */
    radius: CSSProperties
    onClick: () => void
}

/**
 * One account in the list: the shared entity tile fed the account's accent
 * (color + icon) and its live balance. Mirrors `AccountListTile` in the native
 * app — negative balances use the error color.
 */
export function AccountTile({
    id,
    name,
    icon,
    color,
    radius,
    onClick,
}: AccountTileProps) {
    const formatLocale = useFormatLocale()
    const balance = useQuery(api.v1.transactions.queries.balance, {
        accountId: id,
    })
    const accent = normalizeColor(color, ACCOUNT_DEFAULT_COLOR)

    const cents = balance ? Number(balance.balance) : null
    const isNegative = cents !== null && cents < 0

    return (
        <EntityListTile
            radius={radius}
            onClick={onClick}
            leading={
                <EntityAvatar color={accent}>
                    <AccountIcon name={icon} size={22} color={accent} />
                </EntityAvatar>
            }
            title={name}
            trailing={
                <span
                    className={cn(
                        'm3-title-medium tabular-nums',
                        isNegative ? 'text-error' : 'text-on-surface',
                    )}
                >
                    {balance
                        ? formatMoney(
                              Number(balance.balance),
                              balance.currency,
                              formatLocale,
                          )
                        : '—'}
                </span>
            }
        />
    )
}
