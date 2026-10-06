import type { ReactNode } from 'react'
import { AccountIcon } from '@/components/account-icon'
import { CategoryIcon } from '@/components/category-icon'
import { Icon } from '@/components/m3/icon'
import { useReadableAccent } from '@/lib/entity-colors'
import { useFormatLocale, useT } from '@/lib/i18n'
import { formatMoney } from '@/lib/money'
import { cn } from '@/lib/utils'
import type { TransactionTimeStatus } from './helpers'

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
    currency: string
    onClick?: () => void
}

/**
 * One transaction, on the app's raised card surface. Mirrors the native
 * `TransactionRow` widget: title and signed amount on the first line, an
 * optional description under it, and a row of tinted entity glyphs with the
 * time (and an attention marker when the date or time is only estimated).
 */
export function TransactionRow({
    title,
    amountCents,
    dateConfirmed,
    timeLabel,
    timeStatus = 'none',
    description,
    identities = [],
    currency,
    onClick,
}: TransactionRowProps) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const isPositive = amountCents > 0
    const timeNeedsAttention = timeStatus !== 'confirmed'
    const showAttention = !dateConfirmed || timeNeedsAttention
    const sign = amountCents < 0 ? '-' : amountCents > 0 ? '+' : ''
    const amount = `${sign ? `${sign} ` : ''}${formatMoney(Math.abs(amountCents), currency, formatLocale)}`

    const content = (
        <>
            <div className="flex items-start gap-3">
                <span className="min-w-0 flex-1 truncate text-base font-medium">
                    {title}
                </span>
                <span
                    className={cn(
                        'shrink-0 text-base font-semibold tabular-nums',
                        isPositive ? 'text-positive' : 'text-on-surface',
                    )}
                >
                    {amount}
                </span>
            </div>

            {description ? (
                <p className="mt-0.5 truncate text-[13px] text-on-surface-variant">
                    {description}
                </p>
            ) : null}

            {identities.length > 0 || timeLabel || showAttention ? (
                <div className="mt-1.5 flex items-center gap-3">
                    <div className="flex min-w-0 flex-1 flex-wrap items-center gap-1.5">
                        {identities.map((identity) => (
                            <IdentityIcon
                                key={`${identity.type}-${identity.label}`}
                                identity={identity}
                            />
                        ))}
                    </div>
                    <div className="flex shrink-0 items-center gap-1">
                        {showAttention ? (
                            <span
                                role="img"
                                aria-label={t.activity.estimatedDateOrTime}
                                className="flex text-attention"
                            >
                                <Icon name="help" size={15} />
                            </span>
                        ) : null}
                        {timeLabel ? (
                            <span
                                className={cn(
                                    'text-xs font-medium tabular-nums',
                                    timeNeedsAttention
                                        ? 'text-attention'
                                        : 'text-on-surface-variant',
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
        'm3-raised-card w-full rounded-xl px-4 py-3.5 text-left text-on-surface'
    return onClick ? (
        <button
            type="button"
            className={cn(className, 'm3-state-layer cursor-pointer')}
            onClick={onClick}
        >
            {content}
        </button>
    ) : (
        <div className={className}>{content}</div>
    )
}

function IdentityIcon({ identity }: { identity: TransactionRowIdentity }) {
    const paint = useReadableAccent()
    let icon: ReactNode
    if (identity.type === 'account') {
        icon = (
            <AccountIcon
                name={identity.icon}
                size={15}
                color={identity.color}
            />
        )
    } else {
        icon = (
            <CategoryIcon
                name={identity.icon}
                size={15}
                color={identity.color}
            />
        )
    }

    return (
        <span
            role="img"
            className="flex size-6 shrink-0 items-center justify-center rounded-full"
            style={{ backgroundColor: `${paint(identity.color)}29` }}
            title={identity.label}
            aria-label={identity.label}
        >
            {icon}
        </span>
    )
}
