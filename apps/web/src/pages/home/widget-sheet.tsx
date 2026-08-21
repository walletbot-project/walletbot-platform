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
    type DashboardWidth,
    DEFAULT_CURRENCY,
    DEFAULT_VALUE_BACKGROUND,
    filterConfigToJson,
    isFilterEmpty,
    type LayoutCoord,
    mergeWidgetOptions,
    parseFilterConfig,
    parseWidgetOptions,
    type SimpleFilter,
    STAT_AGGREGATIONS,
    type StatAggregation,
    WIDGET_TYPES,
    WIDTH_UNITS,
    type WidgetType,
    widthForUnits,
} from '@wallet-bot/shared'
import { Button, CircularProgress, TextField } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useCallback, useMemo, useState } from 'react'
import { toast } from 'sonner'
import { ColorSwatches } from '@/components/color-swatches'
import { FilterSheet } from '@/components/filters/filter-sheet'
import { BottomSheet } from '@/components/m3/bottom-sheet'
import { ChoiceChip } from '@/components/m3/chip'
import { OptionSheet, type SheetOption } from '@/components/m3/option-sheet'
import { PickerField } from '@/components/m3/picker-field'
import { CURRENCY_CODES, SUGGESTED_CURRENCIES } from '@/lib/currencies'
import { COLOR_OPTIONS } from '@/lib/entity-colors'
import { type Messages, useFormatLocale, useT } from '@/lib/i18n'
import { newId } from '@/lib/new-id'
import { useTheme } from '@/lib/theme'
import type { DashboardWidgetRow } from '@/pages/home/dashboard'
import { readableWidgetBackground } from '@/pages/home/dashboard-colors'
import { widgetTypeLabel, widthLabel } from '@/pages/home/labels'

type WidgetSheetProps = {
    onOpenChange: (open: boolean) => void
    /** The widget being edited, or null when adding a new one. */
    widget: DashboardWidgetRow | null
    /**
     * Where a new widget lands. `null` is the toolbar's add action — a fresh
     * bottom row; a coordinate is one of the grid's `+` placeholders, and
     * `maxUnits` is the free run there, capping the new widget's width
     * (native `showAddWidgetSheet(at:, maxUnits:)`).
     */
    at: LayoutCoord | null
    maxUnits: number | null
    /** Row the new widget lands on when `at` is null — past the last row. */
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
    at,
    maxUnits,
    nextRow,
    nextPosition,
}: WidgetSheetProps) {
    const t = useT()
    const layout = useQuery(api.v1.dashboard.queries.layout)
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
    /**
     * A widget added into one of the grid's `+` placeholders can be no wider
     * than the free run there, so the too-wide options are taken off the
     * picker rather than silently shrunk on save — native caps the width in
     * `_create` because its add sheet has no width control at all.
     */
    const fits = useCallback(
        (candidate: DashboardWidth) =>
            at === null || maxUnits === null
                ? true
                : WIDTH_UNITS[candidate] <= maxUnits,
        [at, maxUnits],
    )
    const cap = useCallback(
        (candidate: DashboardWidth): DashboardWidth =>
            fits(candidate)
                ? candidate
                : (widthForUnits(maxUnits ?? 0) ?? candidate),
        [fits, maxUnits],
    )
    const [width, setWidth] = useState<DashboardWidth>(() =>
        cap(defaultWidthFor(type, widget?.width)),
    )
    const [background, setBackground] = useState<BackgroundStyle>(
        existingOptions.background,
    )
    const [filter, setFilter] = useState<SimpleFilter>(existingFilter)
    const [currencyOpen, setCurrencyOpen] = useState(false)
    const [filterOpen, setFilterOpen] = useState(false)
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
                    width: cap(width),
                    // Either the targeted `+` cell, or — for the toolbar's add
                    // action — a fresh row of its own, where it can never
                    // overlap.
                    options: JSON.stringify({
                        ...JSON.parse(options),
                        layout: at ?? { row: nextRow, col: 0 },
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
                                    setWidth(cap(defaultWidthFor(option)))
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
                    <Section label={t.dashboard.filter}>
                        <PickerField
                            label={t.dashboard.filter}
                            value={
                                isFilterEmpty(filter)
                                    ? ''
                                    : t.dashboard.filterConfigured
                            }
                            placeholder={t.dashboard.noFilter}
                            icon="filter_alt"
                            onClick={() => setFilterOpen(true)}
                            disabled={submitting}
                        />
                    </Section>
                ) : null}

                <Section label={t.dashboard.width}>
                    <div className="flex flex-wrap gap-2">
                        {DASHBOARD_WIDTHS.filter(fits).map((option) => (
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

            {/*
             * The same editor the activity list uses, so a widget's filter is
             * as expressive here as it is on native — tags, amounts, custom
             * ranges and the advanced tree included. Native hides only status
             * for widgets and keeps the advanced toggle on.
             */}
            <FilterSheet
                open={filterOpen}
                onOpenChange={setFilterOpen}
                initial={filter}
                hiddenSections={['status']}
                allowAdvanced
                onApply={setFilter}
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

function BackgroundEditor({
    background,
    onChange,
}: {
    background: BackgroundStyle
    onChange: (next: BackgroundStyle) => void
}) {
    const t = useT()
    const { brightness } = useTheme()
    const modes: BackgroundMode[] = ['none', 'fixed', 'value']
    const value = background.value ?? DEFAULT_VALUE_BACKGROUND
    // The swatches preview each color as the widget will actually paint it in
    // this theme, the way native's `_ColorSwatches` does
    // (apps/native/lib/components/dashboard/add_widget_sheet.dart) — the stored
    // value stays the raw accent.
    const preview = (color: string) =>
        readableWidgetBackground(color, brightness)

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
                    previewColor={preview}
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
                                previewColor={preview}
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
