/**
 * The filter editor, shared by the activity list and the dashboard widget
 * sheet — a port of native's `FilterSheet`
 * (apps/native/lib/components/filter_sheet.dart).
 *
 * It edits a `SimpleFilter` from `packages/shared`, the same model the backend
 * evaluates and both clients store, in two modes: the flat simple form over
 * every dimension, and the tree editor for filters the flat form cannot express.
 * Callers hide the dimensions they own elsewhere via `hiddenSections` — the
 * activity bar keeps text and status, so it hides both — and hidden sections
 * keep their incoming values through apply *and* reset.
 */

import { api } from '@wallet-bot/backend/api'
import {
    ACCOUNT_DIRECTIONS,
    type AccountDirection,
    DATE_PRESETS,
    EMPTY_FILTER,
    type FilterGroup,
    filterToCanonical,
    isSimplyRepresentable,
    type SimpleFilter,
    TAG_MATCHES,
    type TagMatch,
    TXN_STATUSES,
    TXN_TYPES,
} from '@wallet-bot/shared'
import { Button, CircularProgress, IconButton, Switch, TextField } from 'actify'
import { useQuery } from 'convex/react'
import { useMemo, useState } from 'react'
import { BottomSheet } from '@/components/m3/bottom-sheet'
import { ChoiceChip } from '@/components/m3/chip'
import { DateField } from '@/components/m3/date-field'
import { Icon } from '@/components/m3/icon'
import { useT } from '@/lib/i18n'
import {
    AdvancedFilterEditor,
    type FilterOptions,
} from './advanced-filter-editor'
import {
    type ChipOption,
    ChipPicker,
    EmptyHint,
    Section,
    SegmentedChoice,
    SubLabel,
} from './filter-controls'
import {
    accountDirectionLabel,
    centsToText,
    datePresetLabel,
    tagMatchLabel,
    textToCents,
    txnStatusLabel,
    txnTypeLabel,
} from './labels'

/** The dimensions the sheet can render; a caller may hide any of them. */
export type FilterSection =
    | 'type'
    | 'status'
    | 'date'
    | 'accounts'
    | 'categories'
    | 'tags'
    | 'currency'
    | 'amount'
    | 'text'

type FilterSheetProps = {
    open: boolean
    onOpenChange: (open: boolean) => void
    /** The filter to edit; re-read every time the sheet opens. */
    initial: SimpleFilter
    /** Dimensions the caller edits elsewhere. */
    hiddenSections?: readonly FilterSection[]
    /**
     * Whether the simple/advanced toggle is offered. Defaults to "only when
     * nothing is hidden", since the tree ignores `hiddenSections` and could
     * otherwise edit a dimension the caller owns — native's same default.
     */
    allowAdvanced?: boolean
    onApply: (filter: SimpleFilter) => void
}

type EditorMode = 'simple' | 'advanced'

export function FilterSheet({
    open,
    onOpenChange,
    initial,
    hiddenSections = [],
    allowAdvanced,
    onApply,
}: FilterSheetProps) {
    const t = useT()
    const accounts = useQuery(api.v1.accounts.queries.listActive)
    const categories = useQuery(api.v1.categories.queries.listActive)
    const tags = useQuery(api.v1.tags.queries.listActive)

    const [draft, setDraft] = useState<SimpleFilter>(initial)
    const [advancedRoot, setAdvancedRoot] = useState<FilterGroup>(() =>
        filterToCanonical(initial),
    )
    const [mode, setMode] = useState<EditorMode>(
        initial.advancedRoot ? 'advanced' : 'simple',
    )

    // Seed every presentation from the live filter. The sheet is controlled by
    // the `open` prop and stays mounted, so there is no remount to do it —
    // adjust on the prop flip, during render.
    const [wasOpen, setWasOpen] = useState(open)
    if (wasOpen !== open) {
        setWasOpen(open)
        if (open) {
            setDraft(initial)
            setAdvancedRoot(filterToCanonical(initial))
            setMode(initial.advancedRoot ? 'advanced' : 'simple')
        }
    }

    const shows = (section: FilterSection) => !hiddenSections.includes(section)
    const canUseAdvanced = allowAdvanced ?? hiddenSections.length === 0

    // Until the option lists land, "no accounts yet" would be a lie — native
    // shows a spinner in the body for exactly this window (`_optionsFuture`).
    const loadingOptions =
        accounts === undefined || categories === undefined || tags === undefined

    const sortedAccounts = useMemo(() => byName(accounts ?? []), [accounts])
    const sortedCategories = useMemo(
        () => byName(categories ?? []),
        [categories],
    )
    const sortedTags = useMemo(() => byName(tags ?? []), [tags])

    // The currencies the user actually holds — native reads them off the
    // accounts rather than offering the whole ISO catalog.
    const currencies = useMemo(
        () =>
            [...new Set((accounts ?? []).map((account) => account.currency))]
                .sort()
                .map((code) => ({ id: code, label: code })),
        [accounts],
    )

    const options: FilterOptions = useMemo(
        () => ({
            accounts: sortedAccounts.map(toChipOption),
            categories: sortedCategories.map(toChipOption),
            tags: sortedTags.map(toChipOption),
            currencies,
        }),
        [sortedAccounts, sortedCategories, sortedTags, currencies],
    )

    const update = (patch: Partial<SimpleFilter>) =>
        setDraft((current) => ({ ...current, ...patch }))

    const reset = () => {
        // Only the dimensions this sheet renders — a hidden section belongs to
        // the caller and keeps whatever it came in with.
        setDraft((current) => ({
            ...current,
            ...(shows('type') ? { types: [] } : {}),
            ...(shows('status') ? { status: null } : {}),
            ...(shows('date')
                ? { datePreset: null, dateFrom: null, dateTo: null }
                : {}),
            ...(shows('accounts')
                ? {
                      accountIds: [],
                      accountDirection: 'either' as AccountDirection,
                  }
                : {}),
            ...(shows('categories') ? { categoryIds: [] } : {}),
            ...(shows('tags')
                ? {
                      tagIds: [],
                      tagMatch: 'any' as TagMatch,
                      includeSubtags: false,
                  }
                : {}),
            ...(shows('currency') ? { currency: null } : {}),
            ...(shows('amount')
                ? { amountMinCents: null, amountMaxCents: null }
                : {}),
            ...(shows('text') ? { search: null } : {}),
        }))
        if (mode === 'advanced') {
            setAdvancedRoot({ combinator: 'and', children: [] })
        }
    }

    const changeMode = (next: EditorMode) => {
        if (next === mode) return
        // Going advanced starts from what the simple form currently says, so
        // the switch never silently drops the work already done in it.
        if (next === 'advanced') {
            setAdvancedRoot(filterToCanonical({ ...draft, advancedRoot: null }))
        }
        setMode(next)
    }

    const apply = () => {
        onApply(
            mode === 'advanced'
                ? { ...EMPTY_FILTER, advancedRoot }
                : {
                      ...draft,
                      advancedRoot: null,
                      // The amount dimension only means something inside a
                      // single-currency scope — native's `_simpleFilter`.
                      amountMinCents: draft.currency
                          ? draft.amountMinCents
                          : null,
                      amountMaxCents: draft.currency
                          ? draft.amountMaxCents
                          : null,
                  },
        )
        onOpenChange(false)
    }

    // Tags are offered as top level plus, contextually, the children of what is
    // already selected — native's `_buildTagSections`.
    const topLevelTags = sortedTags.filter((tag) => !tag.parentId)
    const subtags = sortedTags.filter(
        (tag) => tag.parentId && draft.tagIds.includes(tag.parentId),
    )

    /**
     * Dropping a tag drops everything under it too: a subtag chip disappears
     * with its parent, and a selection left behind would keep filtering
     * invisibly.
     */
    const setTagIds = (next: string[]) => {
        const removed = draft.tagIds.filter((id) => !next.includes(id))
        if (removed.length === 0) {
            update({ tagIds: next })
            return
        }
        const doomed = new Set(removed)
        let grew = true
        while (grew) {
            grew = false
            for (const tag of sortedTags) {
                if (tag.parentId && doomed.has(tag.parentId)) {
                    if (!doomed.has(tag.id)) {
                        doomed.add(tag.id)
                        grew = true
                    }
                }
            }
        }
        update({ tagIds: next.filter((id) => !doomed.has(id)) })
    }

    const hasCurrency = draft.currency !== null

    return (
        <BottomSheet
            open={open}
            onOpenChange={onOpenChange}
            title={t.filters.title}
            showTitle
            footer={
                <div className="flex gap-3">
                    <Button
                        variant="outlined"
                        className="flex-1"
                        onPress={() => onOpenChange(false)}
                    >
                        {t.common.cancel}
                    </Button>
                    <Button variant="filled" className="flex-1" onPress={apply}>
                        {t.common.apply}
                    </Button>
                </div>
            }
        >
            <div className="flex flex-col gap-6 px-4 pb-6">
                <div className="flex items-center gap-2">
                    {canUseAdvanced ? (
                        <SegmentedChoice
                            label={t.filters.title}
                            value={mode}
                            options={[
                                { value: 'simple', label: t.filters.simple },
                                {
                                    value: 'advanced',
                                    label: t.filters.advanced,
                                },
                            ]}
                            onChange={changeMode}
                        />
                    ) : null}
                    <span className="flex-1" />
                    <IconButton
                        aria-label={t.filters.reset}
                        onPress={reset}
                        className="text-on-surface-variant"
                    >
                        <Icon name="restart_alt" />
                    </IconButton>
                </div>

                {loadingOptions ? (
                    <div className="flex justify-center py-12">
                        <CircularProgress isIndeterminate />
                    </div>
                ) : mode === 'advanced' ? (
                    <AdvancedFilterEditor
                        root={advancedRoot}
                        options={options}
                        onChange={setAdvancedRoot}
                    />
                ) : canUseAdvanced && !isSimplyRepresentable(advancedRoot) ? (
                    <AdvancedOnlyNotice
                        onEditAdvanced={() => setMode('advanced')}
                        onReplaceSimple={() => {
                            setAdvancedRoot({ combinator: 'and', children: [] })
                            setMode('simple')
                        }}
                    />
                ) : (
                    <>
                        {shows('type') ? (
                            <Section title={t.filters.type}>
                                <ChipPicker
                                    options={TXN_TYPES.map((value) => ({
                                        id: value,
                                        label: txnTypeLabel(value, t),
                                    }))}
                                    selected={draft.types}
                                    onToggle={(next) =>
                                        update({
                                            types: TXN_TYPES.filter((value) =>
                                                next.includes(value),
                                            ),
                                        })
                                    }
                                    emptyText=""
                                />
                            </Section>
                        ) : null}

                        {shows('date') ? (
                            <Section title={t.filters.date}>
                                <ChipPicker
                                    options={DATE_PRESETS.map((value) => ({
                                        id: value,
                                        label: datePresetLabel(value, t),
                                    }))}
                                    selected={
                                        // An absolute range wins over a preset
                                        // in the canonical model, so the chips
                                        // read as unselected while one is set.
                                        draft.dateFrom || draft.dateTo
                                            ? []
                                            : draft.datePreset
                                              ? [draft.datePreset]
                                              : []
                                    }
                                    onToggle={(next) =>
                                        update({
                                            datePreset:
                                                DATE_PRESETS.find(
                                                    (value) =>
                                                        value === next[0],
                                                ) ?? null,
                                            dateFrom: null,
                                            dateTo: null,
                                        })
                                    }
                                    emptyText=""
                                    single
                                />
                                <SubLabel>{t.filters.customRange}</SubLabel>
                                <div className="grid grid-cols-2 gap-3">
                                    <DateField
                                        label={t.filters.rangeStart}
                                        compact
                                        value={draft.dateFrom ?? ''}
                                        onChange={(from) =>
                                            update({
                                                dateFrom: from,
                                                // The wire carries a range, not
                                                // a half-open bound, so the far
                                                // end follows until moved.
                                                dateTo: draft.dateTo ?? from,
                                                datePreset: null,
                                            })
                                        }
                                        onClear={() =>
                                            update({
                                                dateFrom: null,
                                                dateTo: null,
                                            })
                                        }
                                    />
                                    <DateField
                                        label={t.filters.rangeEnd}
                                        compact
                                        value={draft.dateTo ?? ''}
                                        onChange={(to) =>
                                            update({
                                                dateFrom: draft.dateFrom ?? to,
                                                dateTo: to,
                                                datePreset: null,
                                            })
                                        }
                                        onClear={() =>
                                            update({
                                                dateFrom: null,
                                                dateTo: null,
                                            })
                                        }
                                    />
                                </div>
                            </Section>
                        ) : null}

                        {shows('accounts') ? (
                            <Section title={t.activity.accounts}>
                                <ChipPicker
                                    options={options.accounts}
                                    selected={draft.accountIds}
                                    onToggle={(accountIds) =>
                                        update({ accountIds })
                                    }
                                    emptyText={t.filters.noAccountsYet}
                                />
                                {draft.accountIds.length > 0 ? (
                                    <div className="flex flex-col items-start gap-1">
                                        <SubLabel>
                                            {t.filters.transferDirection}
                                        </SubLabel>
                                        <SegmentedChoice
                                            label={t.filters.transferDirection}
                                            value={draft.accountDirection}
                                            options={ACCOUNT_DIRECTIONS.map(
                                                (value) => ({
                                                    value,
                                                    label: accountDirectionLabel(
                                                        value,
                                                        t,
                                                    ),
                                                }),
                                            )}
                                            onChange={(accountDirection) =>
                                                update({ accountDirection })
                                            }
                                        />
                                    </div>
                                ) : null}
                            </Section>
                        ) : null}

                        {shows('categories') ? (
                            <Section title={t.activity.categories}>
                                <ChipPicker
                                    options={options.categories}
                                    selected={draft.categoryIds}
                                    onToggle={(categoryIds) =>
                                        update({ categoryIds })
                                    }
                                    emptyText={t.filters.noCategoriesYet}
                                />
                            </Section>
                        ) : null}

                        {shows('tags') ? (
                            <>
                                <Section title={t.activity.tags}>
                                    <ChipPicker
                                        options={topLevelTags.map(toChipOption)}
                                        selected={draft.tagIds}
                                        onToggle={setTagIds}
                                        emptyText={t.filters.noTagsYet}
                                    />
                                </Section>
                                {subtags.length > 0 ? (
                                    <Section title={t.filters.subtags}>
                                        <ChipPicker
                                            options={subtags.map(toChipOption)}
                                            selected={draft.tagIds}
                                            onToggle={setTagIds}
                                            emptyText=""
                                        />
                                    </Section>
                                ) : null}
                                {draft.tagIds.length > 0 ? (
                                    <Section title={t.filters.match}>
                                        <SegmentedChoice
                                            label={t.filters.match}
                                            value={draft.tagMatch}
                                            options={TAG_MATCHES.map(
                                                (value) => ({
                                                    value,
                                                    label: tagMatchLabel(
                                                        value,
                                                        t,
                                                    ),
                                                }),
                                            )}
                                            onChange={(tagMatch) =>
                                                update({ tagMatch })
                                            }
                                        />
                                        <div className="flex items-center justify-between gap-3">
                                            <span className="m3-body-medium text-on-surface">
                                                {t.filters.includeSubtags}
                                            </span>
                                            <Switch
                                                aria-label={
                                                    t.filters.includeSubtags
                                                }
                                                isSelected={
                                                    draft.includeSubtags
                                                }
                                                onChange={(includeSubtags) =>
                                                    update({ includeSubtags })
                                                }
                                            />
                                        </div>
                                    </Section>
                                ) : null}
                            </>
                        ) : null}

                        {shows('status') ? (
                            <Section title={t.filters.status}>
                                <div className="flex flex-wrap gap-2">
                                    <ChoiceChip
                                        label={t.filters.any}
                                        selected={draft.status === null}
                                        onSelect={() =>
                                            update({ status: null })
                                        }
                                    />
                                    {TXN_STATUSES.map((value) => (
                                        <ChoiceChip
                                            key={value}
                                            label={txnStatusLabel(value, t)}
                                            selected={draft.status === value}
                                            onSelect={() =>
                                                update({ status: value })
                                            }
                                        />
                                    ))}
                                </div>
                            </Section>
                        ) : null}

                        {shows('currency') ? (
                            <Section title={t.filters.currency}>
                                <ChipPicker
                                    options={currencies}
                                    selected={
                                        draft.currency ? [draft.currency] : []
                                    }
                                    onToggle={(next) =>
                                        update({ currency: next[0] ?? null })
                                    }
                                    emptyText={t.filters.noCurrenciesYet}
                                    single
                                />
                            </Section>
                        ) : null}

                        {shows('amount') ? (
                            <Section title={t.filters.amount}>
                                {hasCurrency ? (
                                    <div className="grid grid-cols-2 gap-3">
                                        <TextField
                                            variant="outlined"
                                            className="w-full"
                                            label={t.filters.minimum}
                                            inputMode="decimal"
                                            value={centsToText(
                                                draft.amountMinCents,
                                            )}
                                            onChange={(raw) =>
                                                update({
                                                    amountMinCents:
                                                        textToCents(raw),
                                                })
                                            }
                                        />
                                        <TextField
                                            variant="outlined"
                                            className="w-full"
                                            label={t.filters.maximum}
                                            inputMode="decimal"
                                            value={centsToText(
                                                draft.amountMaxCents,
                                            )}
                                            onChange={(raw) =>
                                                update({
                                                    amountMaxCents:
                                                        textToCents(raw),
                                                })
                                            }
                                        />
                                    </div>
                                ) : (
                                    <EmptyHint>
                                        {t.filters.selectCurrencyForAmount}
                                    </EmptyHint>
                                )}
                            </Section>
                        ) : null}

                        {shows('text') ? (
                            <Section title={t.filters.text}>
                                <TextField
                                    variant="outlined"
                                    className="w-full"
                                    aria-label={t.filters.text}
                                    placeholder={t.filters.searchHint}
                                    value={draft.search ?? ''}
                                    onChange={(search) => update({ search })}
                                />
                            </Section>
                        ) : null}
                    </>
                )}
            </div>
        </BottomSheet>
    )
}

function AdvancedOnlyNotice({
    onEditAdvanced,
    onReplaceSimple,
}: {
    onEditAdvanced: () => void
    onReplaceSimple: () => void
}) {
    const t = useT()
    return (
        <div className="flex flex-col gap-3 rounded-xl bg-surface-container-highest p-4">
            <h3 className="m3-title-medium text-on-surface">
                {t.filters.advancedNotice}
            </h3>
            <p className="m3-body-medium text-on-surface-variant">
                {t.filters.advancedWarning}
            </p>
            <div className="flex flex-wrap gap-2">
                <Button variant="filled" onPress={onEditAdvanced}>
                    {t.filters.editAdvanced}
                </Button>
                <Button variant="text" onPress={onReplaceSimple}>
                    {t.filters.createSimpleFilter}
                </Button>
            </div>
        </div>
    )
}

type NamedRow = { id: string; name: string }

function byName<T extends NamedRow>(rows: readonly T[]): T[] {
    return [...rows].sort((left, right) =>
        left.name.localeCompare(right.name, undefined, {
            sensitivity: 'base',
        }),
    )
}

function toChipOption(row: NamedRow): ChipOption {
    return { id: row.id, label: row.name }
}
