import { HelpCircle } from 'lucide-react'
import type { ReactNode } from 'react'
import { AccountIcon } from '@/components/account-icon'
import { CategoryIcon } from '@/components/category-icon'
import { useFormatLocale, useT } from '@/lib/i18n'
import { formatMoney } from '@/lib/money'
import { cn } from '@/lib/utils'
import type { TransactionTimeStatus } from './helpers'
import { formatSignedAmount } from './helpers'

export type TransactionRowIdentity = {
    type: 'account' | 'category'
    label: string
    icon?: string
    color: string
}

type TransactionRowProps = {
    title: string
    /** Signed cents: positive renders green with `+`, negative with `-`. */
    amountCents: number
    dateConfirmed: boolean
    timeLabel?: string
    timeStatus?: TransactionTimeStatus
    description?: string | null
    identities?: readonly TransactionRowIdentity[]
    currency?: string
    currencySymbol?: string
    onClick?: () => void
}

export function TransactionRow({
    title,
    amountCents,
    dateConfirmed,
    timeLabel,
    timeStatus = 'none',
    description,
    identities = [],
    currency,
    currencySymbol = '$',
    onClick,
}: TransactionRowProps) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const isPositive = amountCents > 0
    const timeNeedsAttention = timeStatus !== 'confirmed'
    const showAttention = !dateConfirmed || timeNeedsAttention
    const sign = amountCents < 0 ? '-' : amountCents > 0 ? '+' : ''
    const amount = currency
        ? `${sign ? `${sign} ` : ''}${formatMoney(Math.abs(amountCents), currency, formatLocale)}`
        : formatSignedAmount(amountCents, formatLocale, currencySymbol)

    const content = (
        <>
            <div className="flex items-start justify-between gap-3">
                <span className="min-w-0 flex-1 truncate text-base font-medium text-foreground">
                    {title}
                </span>
                <span
                    className={cn(
                        'shrink-0 text-base font-semibold tabular-nums',
                        isPositive
                            ? 'text-green-600 dark:text-green-500'
                            : 'text-foreground',
                    )}
                >
                    {amount}
                </span>
            </div>

            {description ? (
                <p className="mt-0.5 truncate text-xs text-muted-foreground">
                    {description}
                </p>
            ) : null}

            {identities.length > 0 || timeLabel || showAttention ? (
                <div className="mt-2 flex items-center justify-between gap-3">
                    <div className="flex min-w-0 items-center gap-1.5">
                        {identities.map((identity) => (
                            <IdentityIcon
                                key={`${identity.type}-${identity.label}`}
                                identity={identity}
                            />
                        ))}
                    </div>
                    <div className="flex shrink-0 items-center gap-1">
                        {showAttention ? (
                            <HelpCircle
                                className="size-4 text-amber-600 dark:text-amber-500"
                                aria-label={t.activity.estimatedDateOrTime}
                            />
                        ) : null}
                        {timeLabel ? (
                            <span
                                className={cn(
                                    'text-xs font-medium tabular-nums',
                                    timeNeedsAttention
                                        ? 'text-amber-700 dark:text-amber-500'
                                        : 'text-muted-foreground',
                                )}
                            >
                                {timeLabel}
                            </span>
                        ) : null}
                    </div>
                </div>
            ) : null}
        </>
    )

    const className =
        'w-full rounded-xl border bg-card px-4 py-3 text-left shadow-xs transition-colors'
    return onClick ? (
        <button
            type="button"
            className={cn(
                className,
                'hover:bg-muted/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
            )}
            onClick={onClick}
        >
            {content}
        </button>
    ) : (
        <div className={className}>{content}</div>
    )
}

function IdentityIcon({ identity }: { identity: TransactionRowIdentity }) {
    let icon: ReactNode
    if (identity.type === 'account') {
        icon = (
            <AccountIcon
                name={identity.icon}
                className="size-3.5"
                color={identity.color}
            />
        )
    } else {
        icon = (
            <CategoryIcon
                name={identity.icon}
                className="size-3.5"
                color={identity.color}
            />
        )
    }

    return (
        <span
            role="img"
            className="flex size-6 shrink-0 items-center justify-center rounded-full"
            style={{ backgroundColor: `${identity.color}29` }}
            title={identity.label}
            aria-label={identity.label}
        >
            {icon}
        </span>
    )
}
