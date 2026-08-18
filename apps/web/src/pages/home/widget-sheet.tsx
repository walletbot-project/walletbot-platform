import { api } from '@wallet-bot/backend/api'
import {
    type BackgroundMode,
    type BackgroundStyle,
    BREAKDOWN_CHART_KINDS,
    BREAKDOWN_GROUP_BYS,
    type BreakdownChartKind,
    type BreakdownGroupBy,
    backgroundToJson,
    DASHBOARD_WIDTHS,
    DATE_PRESETS,
    type DashboardWidth,
    DEFAULT_CURRENCY,
    DEFAULT_VALUE_BACKGROUND,
    filterConfigToJson,
    mergeWidgetOptions,
    parseFilterConfig,
    parseWidgetOptions,
    type SimpleFilter,
    STAT_AGGREGATIONS,
    type StatAggregation,
    TXN_TYPES,
    type TxnType,
    WIDGET_TYPES,
    type WidgetType,
} from '@wallet-bot/shared'
import { Button, CircularProgress, TextField } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useMemo, useState } from 'react'
import { toast } from 'sonner'
import { ColorSwatches } from '@/components/color-swatches'
import { BottomSheet } from '@/components/m3/bottom-sheet'
import { ChoiceChip } from '@/components/m3/chip'
import { OptionSheet, type SheetOption } from '@/components/m3/option-sheet'
import { PickerField } from '@/components/m3/picker-field'
import { CURRENCY_CODES, SUGGESTED_CURRENCIES } from '@/lib/currencies'
import { COLOR_OPTIONS } from '@/lib/entity-colors'
import { type Messages, useFormatLocale, useT } from '@/lib/i18n'
import type { DashboardWidgetRow } from '@/pages/home/dashboard'
import { widthLabel } from '@/pages/home/labels'

function newId() {
    return crypto.randomUUID()
}

type WidgetSheetProps = {
    onOpenChange: (open: boolean) => void
    /** The widget being edited, or null when adding a new one. */
    widget: DashboardWidgetRow | null
    /** Row the new widget lands on — one past the last occupied row. */
    nextRow: number
    nextPosition: number
}

/**
 * Add/edit a dashboard widget, porting the native `add_widget_sheet.dart`:
 * type, title, per-type display options, the filter it binds to, its background
 * and its grid width.
 *
 * The filter is edited in simple mode and stored as its own saved filter, so a
 * widget created here is editable from the native app and vice versa.
 */
export function WidgetSheet({
    onOpenChange,
    widget,
    nextRow,
    nextPosition,
}: WidgetSheetProps) {
    const t = useT()
    const layout = useQuery(api.v1.dashboard.queries.layout)
    const accounts = useQuery(api.v1.accounts.queries.listActive)
    const categories = useQuery(api.v1.categories.queries.listActive)
    const createWidget = useMutation(api.v1.dashboard.mutations.createWidget)
    const updateWidget = useMutation(api.v1.dashboard.mutations.updateWidget)
    const createFilter = useMutation(
        api.v1.dashboard.mutations.createSavedFilter,
    )
    const updateFilter = useMutation(
        api.v1.dashboard.mutations.updateSavedFilter,
    )

    const existingOptions = useMemo(
        () => parseWidgetOptions(widget?.options ?? ''),
        [widget],
    )
    const existingFilter = useMemo(() => {
        const saved = widget?.filterId
            ? layout?.filters.find((f) => f.id === widget.filterId)
            : undefined
        return parseFilterConfig(saved?.config ?? '')
    }, [widget, layout])

    // Keyed remount by the sheet host means the initial state below is read
    // once per open, so the form always starts from the current widget.
    const [type, setType] = useState<WidgetType>(
        (WIDGET_TYPES as readonly string[]).includes(widget?.type ?? '')
            ? (widget?.type as WidgetType)
            : 'stat',
    )
    const [title, setTitle] = useState(existingOptions.title)
    const [aggregation, setAggregation] = useState<StatAggregation>(
        existingOptions.aggregation,
    )
    const [limit, setLimit] = useState(String(existingOptions.limit))
    const [currency, setCurrency] = useState(
        existingOptions.currency || DEFAULT_CURRENCY,
    )
    const [groupBy, setGroupBy] = useState<BreakdownGroupBy>(
        existingOptions.groupBy,
    )
    const [chartKind, setChartKind] = useState<BreakdownChartKind>(
        existingOptions.chartKind,
    )
    const [width, setWidth] = useState<DashboardWidth>(
        defaultWidthFor(type, widget?.width),
    )
    const [background, setBackground] = useState<BackgroundStyle>(
        existingOptions.background,
    )
    const [filter, setFilter] = useState<SimpleFilter>(existingFilter)
    const [currencyOpen, setCurrencyOpen] = useState(false)
    const [submitting, setSubmitting] = useState(false)

    const formatLocale = useFormatLocale()
    const currencyOptions: SheetOption[] = useMemo(
        () =>
            CURRENCY_CODES.map((code) => ({
                id: code,
                label: code,
                supporting: new Intl.DisplayNames([formatLocale], {
                    type: 'currency',
                }).of(code),
            })),
        [formatLocale],
    )

    const usesFilter = type !== 'balance'

    const handleSubmit = async () => {
        setSubmitting(true)
        try {
            let filterId: string | null = widget?.filterId ?? null
            if (usesFilter) {
                const config = filterConfigToJson(filter)
                if (filterId) {
                    await updateFilter({ id: filterId, config })
                } else {
                    filterId = newId()
                    await createFilter({
                        id: filterId,
                        name: title || t.dashboard.widget,
                        config,
                    })
                }
            } else {
                filterId = null
            }

            // Same rule the shared parser reads back with: anything that isn't
            // a positive count stores as 5, so the stored JSON never disagrees
            // with what every client displays.
            const parsedLimit = Number.parseInt(limit, 10)
            const options = mergeWidgetOptions(widget?.options ?? '', {
                title,
                ...(type === 'stat' ? { aggregation } : {}),
                ...(type === 'list'
                    ? { limit: parsedLimit > 0 ? parsedLimit : 5 }
                    : {}),
                ...(type === 'balance' ? { currency } : {}),
                ...(type === 'chart' ? { groupBy, chartKind } : {}),
                background: backgroundToJson(background),
            })

            if (widget) {
                await updateWidget({
                    id: widget.id,
                    type,
                    filterId,
                    width,
                    options,
                })
            } else {
                await createWidget({
                    id: newId(),
                    type,
                    ...(filterId ? { filterId } : {}),
                    position: nextPosition,
                    width,
                    // A new tile lands on its own row, so it can never overlap.
                    options: JSON.stringify({
                        ...JSON.parse(options),
                        layout: { row: nextRow, col: 0 },
                    }),
                })
            }
            onOpenChange(false)
        } catch {
            toast.error(t.dashboard.saveFailed)
        } finally {
            setSubmitting(false)
        }
    }

    return (
        <BottomSheet
            // Mounted conditionally by Home; while rendered it is always open.
            open
            onOpenChange={onOpenChange}
            title={widget ? t.dashboard.editWidget : t.dashboard.addWidget}
            showTitle
        >
            <div className="flex flex-col gap-6 px-4 pb-8">
                <Section label={t.dashboard.widgetType}>
                    <div className="flex flex-wrap gap-2">
                        {WIDGET_TYPES.map((option) => (
                            <ChoiceChip
                                key={option}
                                label={widgetTypeLabel(option, t)}
                                selected={option === type}
                                onSelect={() => {
                                    // Re-tapping the selected chip must not
                                    // reset a hand-picked width.
                                    if (option === type) return
                                    setType(option)
                                    setWidth(defaultWidthFor(option))
                                }}
                            />
                        ))}
                    </div>
                </Section>

                <TextField
                    variant="outlined"
                    className="w-full"
                    label={t.dashboard.widgetTitle}
                    value={title}
                    onChange={setTitle}
                    isDisabled={submitting}
                />

                {type === 'stat' ? (
                    <Section label={t.dashboard.aggregation}>
                        <div className="flex flex-wrap gap-2">
                            {STAT_AGGREGATIONS.map((option) => (
                                <ChoiceChip
                                    key={option}
                                    label={aggregationLabel(option, t)}
                                    selected={option === aggregation}
                                    onSelect={() => setAggregation(option)}
                                />
                            ))}
                        </div>
                    </Section>
                ) : null}

                {type === 'list' ? (
                    <TextField
                        variant="outlined"
                        className="w-full"
                        label={t.dashboard.rowLimit}
                        value={limit}
                        onChange={setLimit}
                        inputMode="numeric"
                        isDisabled={submitting}
                    />
                ) : null}

                {type === 'balance' ? (
                    <PickerField
                        label={t.common.currency}
                        value={currency}
                        onClick={() => setCurrencyOpen(true)}
                        disabled={submitting}
                    />
                ) : null}

                {type === 'chart' ? (
                    <>
                        <Section label={t.dashboard.groupBy}>
                            <div className="flex flex-wrap gap-2">
                                {BREAKDOWN_GROUP_BYS.map((option) => (
                                    <ChoiceChip
                                        key={option}
                                        label={groupByLabel(option, t)}
                                        selected={option === groupBy}
                                        onSelect={() => setGroupBy(option)}
                                    />
                                ))}
                            </div>
                        </Section>
                        <Section label={t.dashboard.chartKind}>
                            <div className="flex flex-wrap gap-2">
                                {BREAKDOWN_CHART_KINDS.map((option) => (
                                    <ChoiceChip
                                        key={option}
                                        label={chartKindLabel(option, t)}
                                        selected={option === chartKind}
                                        onSelect={() => setChartKind(option)}
                                    />
                                ))}
                            </div>
                        </Section>
                    </>
                ) : null}

                {usesFilter ? (
                    <FilterEditor
                        filter={filter}
                        onChange={setFilter}
                        accounts={accounts ?? []}
                        categories={categories ?? []}
                    />
                ) : null}

                <Section label={t.dashboard.width}>
                    <div className="flex flex-wrap gap-2">
                        {DASHBOARD_WIDTHS.map((option) => (
                            <ChoiceChip
                                key={option}
                                label={widthLabel(option, t)}
                                selected={option === width}
                                onSelect={() => setWidth(option)}
                            />
                        ))}
                    </div>
                </Section>

                <BackgroundEditor
                    background={background}
                    onChange={setBackground}
                />

                <Button
                    variant="filled"
                    className="w-full"
                    isDisabled={submitting}
                    onPress={() => void handleSubmit()}
                >
                    {submitting ? (
                        <CircularProgress isIndeterminate size="xs" />
                    ) : null}
                    {widget ? t.common.save : t.common.create}
                </Button>
            </div>

            <OptionSheet
                open={currencyOpen}
                onOpenChange={setCurrencyOpen}
                title={t.accounts.chooseCurrency}
                options={currencyOptions}
                selected={currency}
                onSelect={(code) => {
                    setCurrency(code)
                    setCurrencyOpen(false)
                }}
                searchPlaceholder={t.accounts.searchCurrency}
                suggested={SUGGESTED_CURRENCIES}
            />
        </BottomSheet>
    )
}

function Section({
    label,
    children,
}: {
    label: string
    children: React.ReactNode
}) {
    return (
        <section className="flex flex-col gap-2">
            <h3 className="m3-label-large text-on-surface">{label}</h3>
            {children}
        </section>
    )
}

/** The simple-mode filter editor: the dimensions the design doc calls simple. */
function FilterEditor({
    filter,
    onChange,
    accounts,
    categories,
}: {
    filter: SimpleFilter
    onChange: (next: SimpleFilter) => void
    accounts: { id: string; name: string }[]
    categories: { id: string; name: string }[]
}) {
    const t = useT()

    if (filter.advancedRoot) {
        return (
            <Section label={t.dashboard.filter}>
                <p className="m3-body-medium rounded-lg bg-surface-container-high px-3 py-2 text-on-surface-variant">
                    {t.dashboard.advancedFilterReadOnly}
                </p>
            </Section>
        )
    }

    const toggle = <T,>(list: T[], value: T): T[] =>
        list.includes(value)
            ? list.filter((item) => item !== value)
            : [...list, value]

    return (
        <>
            <Section label={t.dashboard.movementTypes}>
                <div className="flex flex-wrap gap-2">
                    {TXN_TYPES.map((option) => (
                        <ChoiceChip
                            key={option}
                            label={txnTypeLabel(option, t)}
                            selected={filter.types.includes(option)}
                            onSelect={() =>
                                onChange({
                                    ...filter,
                                    types: toggle(filter.types, option),
                                })
                            }
                        />
                    ))}
                </div>
            </Section>

            <Section label={t.dashboard.period}>
                <div className="flex flex-wrap gap-2">
                    {DATE_PRESETS.map((option) => (
                        <ChoiceChip
                            key={option}
                            label={datePresetLabel(option, t)}
                            selected={filter.datePreset === option}
                            onSelect={() =>
                                onChange({
                                    ...filter,
                                    datePreset:
                                        filter.datePreset === option
                                            ? null
                                            : option,
                                    dateFrom: null,
                                    dateTo: null,
                                })
                            }
                        />
                    ))}
                </div>
            </Section>

            {accounts.length > 0 ? (
                <Section label={t.activity.accounts}>
                    <div className="flex flex-wrap gap-2">
                        {accounts.map((account) => (
                            <ChoiceChip
                                key={account.id}
                                label={account.name}
                                selected={filter.accountIds.includes(
                                    account.id,
                                )}
                                onSelect={() =>
                                    onChange({
                                        ...filter,
                                        accountIds: toggle(
                                            filter.accountIds,
                                            account.id,
                                        ),
                                    })
                                }
                            />
                        ))}
                    </div>
                </Section>
            ) : null}

            {categories.length > 0 ? (
                <Section label={t.activity.categories}>
                    <div className="flex flex-wrap gap-2">
                        {categories.map((category) => (
                            <ChoiceChip
                                key={category.id}
                                label={category.name}
                                selected={filter.categoryIds.includes(
                                    category.id,
                                )}
                                onSelect={() =>
                                    onChange({
                                        ...filter,
                                        categoryIds: toggle(
                                            filter.categoryIds,
                                            category.id,
                                        ),
                                    })
                                }
                            />
                        ))}
                    </div>
                </Section>
            ) : null}

            <Section label={t.dashboard.currencyScope}>
                <div className="flex flex-wrap gap-2">
                    {SUGGESTED_CURRENCIES.map((code) => (
                        <ChoiceChip
                            key={code}
                            label={code}
                            selected={filter.currency === code}
                            onSelect={() =>
                                onChange({
                                    ...filter,
                                    currency:
                                        filter.currency === code ? null : code,
                                })
                            }
                        />
                    ))}
                </div>
            </Section>
        </>
    )
}

function BackgroundEditor({
    background,
    onChange,
}: {
    background: BackgroundStyle
    onChange: (next: BackgroundStyle) => void
}) {
    const t = useT()
    const modes: BackgroundMode[] = ['none', 'fixed', 'value']
    const value = background.value ?? DEFAULT_VALUE_BACKGROUND

    return (
        <Section label={t.dashboard.background}>
            <div className="flex flex-wrap gap-2">
                {modes.map((mode) => (
                    <ChoiceChip
                        key={mode}
                        label={backgroundModeLabel(mode, t)}
                        selected={background.mode === mode}
                        onSelect={() =>
                            onChange({
                                ...background,
                                mode,
                                ...(mode === 'value' && !background.value
                                    ? { value: DEFAULT_VALUE_BACKGROUND }
                                    : {}),
                            })
                        }
                    />
                ))}
            </div>

            {background.mode === 'fixed' ? (
                <ColorSwatches
                    value={background.fixedColor ?? COLOR_OPTIONS[0]}
                    onChange={(color) =>
                        onChange({ ...background, fixedColor: color })
                    }
                    options={COLOR_OPTIONS}
                />
            ) : null}

            {background.mode === 'value' ? (
                <div className="flex flex-col gap-3">
                    <div className="grid grid-cols-2 gap-3">
                        <TextField
                            variant="outlined"
                            className="w-full"
                            label={t.dashboard.thresholdLow}
                            value={String(value.low)}
                            onChange={(next) =>
                                onChange({
                                    ...background,
                                    value: {
                                        ...value,
                                        low: Number.parseFloat(next) || 0,
                                    },
                                })
                            }
                            inputMode="decimal"
                        />
                        <TextField
                            variant="outlined"
                            className="w-full"
                            label={t.dashboard.thresholdHigh}
                            value={String(value.high)}
                            onChange={(next) =>
                                onChange({
                                    ...background,
                                    value: {
                                        ...value,
                                        high: Number.parseFloat(next) || 0,
                                    },
                                })
                            }
                            inputMode="decimal"
                        />
                    </div>
                    {(
                        [
                            ['lowColor', t.dashboard.belowLow],
                            ['betweenColor', t.dashboard.betweenThresholds],
                            ['highColor', t.dashboard.aboveHigh],
                        ] as const
                    ).map(([key, label]) => (
                        <div key={key} className="flex flex-col gap-2">
                            <span className="m3-body-small text-on-surface-variant">
                                {label}
                            </span>
                            <ColorSwatches
                                value={value[key]}
                                onChange={(color) =>
                                    onChange({
                                        ...background,
                                        value: { ...value, [key]: color },
                                    })
                                }
                                options={COLOR_OPTIONS}
                            />
                        </div>
                    ))}
                </div>
            ) : null}
        </Section>
    )
}

function defaultWidthFor(type: WidgetType, stored?: string): DashboardWidth {
    if (stored && (DASHBOARD_WIDTHS as readonly string[]).includes(stored)) {
        return stored as DashboardWidth
    }
    switch (type) {
        case 'stat':
            return 'third'
        case 'balance':
            return 'half'
        default:
            return 'full'
    }
}

function widgetTypeLabel(type: WidgetType, t: Messages): string {
    switch (type) {
        case 'stat':
            return t.dashboard.typeStat
        case 'list':
            return t.dashboard.typeList
        case 'balance':
            return t.dashboard.typeBalance
        case 'chart':
            return t.dashboard.typeChart
    }
}

function aggregationLabel(value: StatAggregation, t: Messages): string {
    switch (value) {
        case 'sum':
            return t.dashboard.aggregationSum
        case 'net':
            return t.dashboard.aggregationNet
        case 'count':
            return t.dashboard.aggregationCount
    }
}

function groupByLabel(value: BreakdownGroupBy, t: Messages): string {
    switch (value) {
        case 'category':
            return t.dashboard.groupByCategory
        case 'account':
            return t.dashboard.groupByAccount
        case 'month':
            return t.dashboard.groupByMonth
    }
}

function chartKindLabel(value: BreakdownChartKind, t: Messages): string {
    switch (value) {
        case 'pie':
            return t.dashboard.chartPie
        case 'bar':
            return t.dashboard.chartBar
        case 'line':
            return t.dashboard.chartLine
    }
}

function backgroundModeLabel(value: BackgroundMode, t: Messages): string {
    switch (value) {
        case 'none':
            return t.dashboard.backgroundNone
        case 'fixed':
            return t.dashboard.backgroundFixed
        case 'value':
            return t.dashboard.backgroundValue
    }
}

function txnTypeLabel(value: TxnType, t: Messages): string {
    switch (value) {
        case 'expense':
            return t.activity.typeExpense
        case 'income':
            return t.activity.typeIncome
        case 'transfer':
            return t.activity.typeTransfer
        case 'balance_adjustment':
            return t.activity.typeBalanceAdjustment
    }
}

function datePresetLabel(
    value: (typeof DATE_PRESETS)[number],
    t: Messages,
): string {
    switch (value) {
        case 'today':
            return t.dashboard.presetToday
        case 'this_week':
            return t.dashboard.presetThisWeek
        case 'this_month':
            return t.dashboard.presetThisMonth
        case 'last_month':
            return t.dashboard.presetLastMonth
        case 'this_year':
            return t.dashboard.presetThisYear
    }
}
