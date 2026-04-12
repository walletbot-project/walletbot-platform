import { format, isToday, isYesterday, parseISO } from 'date-fns'
import type { LucideIcon } from 'lucide-react'
import { ArrowDownLeft, ArrowLeftRight, ArrowUpRight } from 'lucide-react'

const CURRENCY_SYMBOLS: Record<string, string> = {
    USD: '$',
    ARS: 'AR$',
    EUR: '\u20AC',
    BRL: 'R$',
}

export function formatCurrency(cents: number, currency: string): string {
    const value = Math.abs(cents) / 100
    const symbol = CURRENCY_SYMBOLS[currency] ?? currency
    const formatted = value.toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    })
    return cents < 0 ? `-${symbol} ${formatted}` : `${symbol} ${formatted}`
}

export function formatDate(dateStr: string): string {
    const date = parseISO(dateStr)
    return format(date, 'MMM d, yyyy')
}

export function formatDateRelative(dateStr: string): string {
    const date = parseISO(dateStr)
    if (isToday(date)) return 'Today'
    if (isYesterday(date)) return 'Yesterday'
    return format(date, 'MMM d')
}

export function formatDateShort(dateStr: string): string {
    const date = parseISO(dateStr)
    return format(date, 'MMM d')
}

export function todayString(): string {
    return format(new Date(), 'yyyy-MM-dd')
}

export function firstOfMonthString(): string {
    const now = new Date()
    return format(new Date(now.getFullYear(), now.getMonth(), 1), 'yyyy-MM-dd')
}

export function lastOfMonthString(): string {
    const now = new Date()
    return format(
        new Date(now.getFullYear(), now.getMonth() + 1, 0),
        'yyyy-MM-dd',
    )
}

type TxType = 'expense' | 'income' | 'transfer'

export const TX_TYPE_ICONS: Record<TxType, LucideIcon> = {
    expense: ArrowDownLeft,
    income: ArrowUpRight,
    transfer: ArrowLeftRight,
}

export function txTypeColor(type: TxType): string {
    switch (type) {
        case 'expense':
            return 'text-red-600 dark:text-red-400'
        case 'income':
            return 'text-green-600 dark:text-green-400'
        case 'transfer':
            return 'text-blue-600 dark:text-blue-400'
    }
}

export function txTypeBgColor(type: TxType): string {
    switch (type) {
        case 'expense':
            return 'bg-red-100 dark:bg-red-900/30'
        case 'income':
            return 'bg-green-100 dark:bg-green-900/30'
        case 'transfer':
            return 'bg-blue-100 dark:bg-blue-900/30'
    }
}

export function frequencyLabel(frequency: string, interval: number): string {
    const unit =
        frequency === 'daily'
            ? 'day'
            : frequency === 'weekly'
              ? 'week'
              : frequency === 'monthly'
                ? 'month'
                : 'year'
    if (interval === 1) return `Every ${unit}`
    return `Every ${interval} ${unit}s`
}
