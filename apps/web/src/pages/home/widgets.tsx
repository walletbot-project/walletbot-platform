import { api } from '@wallet-bot/backend/api'
import type {
    BreakdownChartKind,
    BreakdownGroupBy,
    StatAggregation,
    WidgetOptions,
} from '@wallet-bot/shared'
import { useQuery } from 'convex/react'
import {
    Bar,
    BarChart,
    CartesianGrid,
    Cell,
    Line,
    LineChart,
    Pie,
    PieChart,
    ResponsiveContainer,
    Tooltip,
    XAxis,
} from 'recharts'
import { Skeleton } from '@/components/ui/skeleton'
import { COLOR_OPTIONS } from '@/lib/entity-colors'
import { useFormatLocale, useT } from '@/lib/i18n'
import { formatMoney } from '@/lib/money'
import { useTheme } from '@/lib/theme'
import { DashboardCell } from '@/pages/home/dashboard-cell'
import { resolveBackground } from '@/pages/home/dashboard-colors'

/** The empty (match-all) filter, used when a widget's saved filter is gone. */
const MATCH_ALL = '{"combinator":"and","children":[]}'

export type WidgetSpec = {
    id: string
    type: string
    options: WidgetOptions
    /** The resolved canonical config JSON of the widget's saved filter. */
    config: string
    /** Currency scope of the widget's filter, for money formatting. */
    currency: string | null
}

const STAT_ICONS: Record<StatAggregation, string> = {
    count: 'format_list_numbered',
    net: 'swap_vert',
    sum: 'calculate',
}

export function StatWidget({ spec }: { spec: WidgetSpec }) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const { brightness } = useTheme()
    const result = useQuery(api.v1.dashboard.queries.stat, {
        config: spec.config || MATCH_ALL,
        aggregation: spec.options.aggregation,
    })

    const displayValue =
        result === undefined
            ? null
            : spec.options.aggregation === 'count'
              ? result.count
              : Number(result.amountCents) / 100

    return (
        <DashboardCell
            title={spec.options.title}
            icon={STAT_ICONS[spec.options.aggregation]}
            minHeight={128}
            backgroundColor={resolveBackground(
                spec.options.background,
                displayValue,
                brightness,
            )}
        >
            {result === undefined ? (
                <Skeleton className="h-8 w-24" />
            ) : (
                <p className="m3-title-large truncate font-extrabold text-on-surface">
                    {spec.options.aggregation === 'count'
                        ? result.count
                        : formatStatMoney(
                              Number(result.amountCents),
                              spec.currency,
                              formatLocale,
                          )}
                </p>
            )}
            {result?.truncated ? (
                <p className="m3-body-small mt-1 text-on-surface-variant">
                    {t.dashboard.partialResult}
                </p>
            ) : null}
        </DashboardCell>
    )
}

/** Counts render bare; money prefixes the currency and only signs negatives. */
function formatStatMoney(
    cents: number,
    currency: string | null,
    locale: string,
): string {
    if (currency) return formatMoney(cents, currency, locale)
    const sign = cents < 0 ? '-' : ''
    return `${sign}${new Intl.NumberFormat(locale, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    }).format(Math.abs(cents) / 100)}`
}

export function BalanceCardWidget({ spec }: { spec: WidgetSpec }) {
    const formatLocale = useFormatLocale()
    const { brightness } = useTheme()
    const currency = spec.options.currency
    const result = useQuery(api.v1.dashboard.queries.currencyBalance, {
        currency,
    })

    return (
        <DashboardCell
            title={spec.options.title}
            icon="account_balance_wallet"
            minHeight={128}
            trailing={
                <span className="m3-label-small rounded-full bg-secondary-container/60 px-2 py-0.5 font-extrabold text-on-secondary-container">
                    {currency}
                </span>
            }
            backgroundColor={resolveBackground(
                spec.options.background,
                result === undefined ? null : Number(result.balance) / 100,
                brightness,
            )}
        >
            {result === undefined ? (
                <Skeleton className="h-9 w-32" />
            ) : (
                <p className="m3-headline-small truncate font-extrabold text-on-surface">
                    {formatMoney(
                        Number(result.balance),
                        currency,
                        formatLocale,
                    )}
                </p>
            )}
        </DashboardCell>
    )
}

export function TransactionListWidget({ spec }: { spec: WidgetSpec }) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const { brightness } = useTheme()
    const rows = useQuery(api.v1.dashboard.queries.transactions, {
        config: spec.config || MATCH_ALL,
        limit: spec.options.limit,
    })

    return (
        <DashboardCell
            title={spec.options.title}
            icon="receipt_long"
            minHeight={160}
            backgroundColor={resolveBackground(
                spec.options.background,
                rows === undefined ? null : rows.length,
                brightness,
            )}
        >
            {rows === undefined ? (
                <div className="flex flex-col gap-2">
                    <Skeleton className="h-6 w-full" />
                    <Skeleton className="h-6 w-full" />
                </div>
            ) : rows.length === 0 ? (
                <p className="m3-body-medium text-on-surface-variant">
                    {t.dashboard.noMovementsYet}
                </p>
            ) : (
                <ul className="flex flex-col pb-6">
                    {rows.map((row, index) => (
                        <li
                            key={row.id}
                            className={
                                index === 0
                                    ? 'flex items-center gap-3 py-2'
                                    : 'flex items-center gap-3 border-outline-variant border-t py-2'
                            }
                        >
                            <span className="m3-body-medium min-w-0 flex-1 truncate text-on-surface">
                                {row.name}
                            </span>
                            <span
                                className={
                                    row.type === 'income'
                                        ? 'm3-body-medium shrink-0 tabular-nums text-positive'
                                        : 'm3-body-medium shrink-0 tabular-nums text-on-surface'
                                }
                            >
                                {formatMoney(
                                    signedDisplayCents(row.type, row.amount),
                                    row.currency,
                                    formatLocale,
                                )}
                            </span>
                        </li>
                    ))}
                </ul>
            )}
        </DashboardCell>
    )
}

/** Expenses read negative in a list; everything else keeps its stored sign. */
function signedDisplayCents(type: string, amount: bigint): number {
    const value = Number(amount)
    if (type === 'expense') return -Math.abs(value)
    if (type === 'income') return Math.abs(value)
    return value
}

const GROUP_BY_ICONS: Record<BreakdownGroupBy, string> = {
    category: 'donut_small',
    account: 'account_balance',
    month: 'calendar_month',
}

export function BreakdownChartWidget({ spec }: { spec: WidgetSpec }) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const { brightness } = useTheme()
    const result = useQuery(api.v1.dashboard.queries.breakdown, {
        config: spec.config || MATCH_ALL,
        groupBy: spec.options.groupBy,
    })

    const slices = (result?.slices ?? []).map((slice, index) => ({
        key: slice.key,
        label: slice.label,
        value: Number(slice.totalCents) / 100,
        color: slice.colorHex ?? COLOR_OPTIONS[index % COLOR_OPTIONS.length],
    }))
    const total = slices.reduce((sum, slice) => sum + slice.value, 0)

    return (
        <DashboardCell
            title={spec.options.title}
            icon={GROUP_BY_ICONS[spec.options.groupBy]}
            minHeight={240}
            backgroundColor={resolveBackground(
                spec.options.background,
                result === undefined ? null : total,
                brightness,
            )}
        >
            {result === undefined ? (
                <Skeleton className="h-40 w-full" />
            ) : slices.length === 0 ? (
                <p className="m3-body-medium text-on-surface-variant">
                    {t.dashboard.noMovementsYet}
                </p>
            ) : (
                <div className="h-48 w-full pb-4">
                    <BreakdownChart
                        kind={spec.options.chartKind}
                        slices={slices}
                        currency={spec.currency}
                        locale={formatLocale}
                    />
                </div>
            )}
        </DashboardCell>
    )
}

type Slice = { key: string; label: string; value: number; color: string }

function BreakdownChart({
    kind,
    slices,
    currency,
    locale,
}: {
    kind: BreakdownChartKind
    slices: Slice[]
    currency: string | null
    locale: string
}) {
    const formatValue = (value: number) =>
        currency
            ? formatMoney(Math.round(value * 100), currency, locale)
            : new Intl.NumberFormat(locale, {
                  maximumFractionDigits: 2,
              }).format(value)

    const tooltip = (
        <Tooltip
            formatter={(value) =>
                formatValue(typeof value === 'number' ? value : 0)
            }
            contentStyle={{
                background: 'var(--md-sys-color-surface-container-high)',
                border: '1px solid var(--md-sys-color-outline-variant)',
                borderRadius: 12,
                color: 'var(--md-sys-color-on-surface)',
            }}
        />
    )
    const axis = (
        <XAxis
            dataKey="label"
            tick={{
                fontSize: 11,
                fill: 'var(--md-sys-color-on-surface-variant)',
            }}
            axisLine={false}
            tickLine={false}
        />
    )

    if (kind === 'pie') {
        return (
            <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                    <Pie
                        data={slices}
                        dataKey="value"
                        nameKey="label"
                        innerRadius="45%"
                        outerRadius="80%"
                        strokeWidth={0}
                    >
                        {slices.map((slice) => (
                            <Cell key={slice.key} fill={slice.color} />
                        ))}
                    </Pie>
                    {tooltip}
                </PieChart>
            </ResponsiveContainer>
        )
    }

    if (kind === 'bar') {
        return (
            <ResponsiveContainer width="100%" height="100%">
                <BarChart data={slices}>
                    <CartesianGrid
                        vertical={false}
                        stroke="var(--md-sys-color-outline-variant)"
                    />
                    {axis}
                    {tooltip}
                    <Bar dataKey="value" radius={[6, 6, 0, 0]}>
                        {slices.map((slice) => (
                            <Cell key={slice.key} fill={slice.color} />
                        ))}
                    </Bar>
                </BarChart>
            </ResponsiveContainer>
        )
    }

    return (
        <ResponsiveContainer width="100%" height="100%">
            <LineChart data={slices}>
                <CartesianGrid
                    vertical={false}
                    stroke="var(--md-sys-color-outline-variant)"
                />
                {axis}
                {tooltip}
                <Line
                    type="monotone"
                    dataKey="value"
                    stroke="var(--md-sys-color-primary)"
                    strokeWidth={2}
                    dot={false}
                />
            </LineChart>
        </ResponsiveContainer>
    )
}
