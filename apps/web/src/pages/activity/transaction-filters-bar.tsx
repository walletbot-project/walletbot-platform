import { api } from '@wallet-bot/backend/api'
import { useQuery } from 'convex/react'
import { useState } from 'react'
import type { DateRange } from 'react-day-picker'
import { ChoiceChip, InputChip } from '@/components/m3/chip'
import { Icon } from '@/components/m3/icon'
import { Button } from '@/components/ui/button'
import { Calendar } from '@/components/ui/calendar'
import { Input } from '@/components/ui/input'
import {
    Popover,
    PopoverContent,
    PopoverTrigger,
} from '@/components/ui/popover'
import { Separator } from '@/components/ui/separator'
import {
    Sheet,
    SheetClose,
    SheetContent,
    SheetFooter,
    SheetHeader,
    SheetTitle,
    SheetTrigger,
} from '@/components/ui/sheet'
import { type Messages, useFormatLocale, useT } from '@/lib/i18n'
import {
    advancedFilterCount,
    EMPTY_FILTERS,
    formatNumericDate,
    hasAdvancedFilters,
    type TransactionFilters,
} from './helpers'

type NamedEntity = { id: string; name: string }

type TransactionFiltersBarProps = {
    filters: TransactionFilters
    onChange: (next: TransactionFilters) => void
}

export function TransactionFiltersBar({
    filters,
    onChange,
}: TransactionFiltersBarProps) {
    const t = useT()
    const accounts = useQuery(api.v1.accounts.queries.listActive)
    const categories = useQuery(api.v1.categories.queries.listActive)
    const tags = useQuery(api.v1.tags.queries.listActive)

    return (
        <div className="flex flex-col gap-2.5">
            <div className="flex items-center gap-2 px-4">
                <div className="relative flex-1">
                    <Icon
                        name="search"
                        filled
                        className="pointer-events-none absolute top-1/2 left-4 -translate-y-1/2 text-on-surface-variant"
                    />
                    <Input
                        value={filters.search}
                        onChange={(e) =>
                            onChange({ ...filters, search: e.target.value })
                        }
                        placeholder={t.activity.search}
                        className="h-13 rounded-[32px] border-none bg-surface-container-highest pr-5 pl-13 text-on-surface shadow-none"
                    />
                </div>
                <FiltersSheet
                    filters={filters}
                    onChange={onChange}
                    accounts={accounts ?? []}
                    categories={categories ?? []}
                    tags={tags ?? []}
                />
            </div>

            {hasAdvancedFilters(filters) ? (
                <ActiveFilterChips
                    filters={filters}
                    onChange={onChange}
                    accounts={accounts ?? []}
                    categories={categories ?? []}
                    tags={tags ?? []}
                />
            ) : null}
        </div>
    )
}

type FiltersSheetProps = {
    filters: TransactionFilters
    onChange: (next: TransactionFilters) => void
    accounts: NamedEntity[]
    categories: NamedEntity[]
    tags: NamedEntity[]
}

function FiltersSheet({
    filters,
    onChange,
    accounts,
    categories,
    tags,
}: FiltersSheetProps) {
    const t = useT()
    const [open, setOpen] = useState(false)
    const [draft, setDraft] = useState<TransactionFilters>(filters)
    const count = advancedFilterCount(filters)

    const handleOpenChange = (next: boolean) => {
        // Seed the draft from the live filters each time the sheet opens.
        if (next) setDraft(filters)
        setOpen(next)
    }

    const apply = () => {
        onChange(draft)
        setOpen(false)
    }

    const clear = () => {
        setDraft({
            ...EMPTY_FILTERS,
            // Search lives in the bar, not the sheet — keep it.
            search: draft.search,
        })
    }

    const range: DateRange | undefined =
        draft.dateFrom || draft.dateTo
            ? { from: draft.dateFrom, to: draft.dateTo }
            : undefined

    return (
        <Sheet open={open} onOpenChange={handleOpenChange}>
            <SheetTrigger
                render={
                    <button
                        type="button"
                        className="m3-state-layer relative flex size-10 shrink-0 cursor-pointer items-center justify-center rounded-full bg-secondary-container text-on-secondary-container"
                        aria-label={t.activity.filters}
                    />
                }
            >
                <Icon name="tune" filled />
                {count > 0 ? (
                    <span className="absolute -top-0.5 -right-0.5 flex min-h-4.5 min-w-4.5 items-center justify-center rounded-[10px] bg-primary px-1.5 text-[11px] font-bold text-on-primary">
                        {count}
                    </span>
                ) : null}
            </SheetTrigger>
            <SheetContent
                side="bottom"
                showCloseButton={false}
                className="max-h-[90dvh] gap-0 rounded-t-[28px] border-none bg-surface-container-low text-on-surface"
            >
                <SheetHeader className="flex-row items-center justify-between">
                    <SheetTitle>{t.activity.filters}</SheetTitle>
                    <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        onClick={clear}
                    >
                        {t.common.clear}
                    </Button>
                </SheetHeader>
                <Separator />

                <div className="flex-1 space-y-6 overflow-y-auto p-4">
                    <section className="space-y-2">
                        <SectionTitle>{t.activity.dateRange}</SectionTitle>
                        <DateRangeField
                            range={range}
                            onSelect={(next) =>
                                setDraft({
                                    ...draft,
                                    dateFrom: next?.from,
                                    dateTo: next?.to,
                                })
                            }
                            onClear={() =>
                                setDraft({
                                    ...draft,
                                    dateFrom: undefined,
                                    dateTo: undefined,
                                })
                            }
                        />
                    </section>

                    <section className="space-y-2">
                        <SectionTitle>{t.activity.accounts}</SectionTitle>
                        <TogglePicker
                            entities={accounts}
                            selected={draft.accountIds}
                            onChange={(accountIds) =>
                                setDraft({ ...draft, accountIds })
                            }
                            emptyText={t.activity.noAccounts}
                        />
                    </section>

                    <section className="space-y-2">
                        <SectionTitle>{t.activity.categories}</SectionTitle>
                        <TogglePicker
                            entities={categories}
                            selected={draft.categoryIds}
                            onChange={(categoryIds) =>
                                setDraft({ ...draft, categoryIds })
                            }
                            emptyText={t.activity.noCategories}
                        />
                    </section>

                    <section className="space-y-2">
                        <SectionTitle>{t.activity.tags}</SectionTitle>
                        <TogglePicker
                            entities={tags}
                            selected={draft.tagIds}
                            onChange={(tagIds) =>
                                setDraft({ ...draft, tagIds })
                            }
                            emptyText={t.activity.noTags}
                        />
                    </section>
                </div>

                <Separator />
                <SheetFooter className="flex-row gap-2">
                    <SheetClose
                        render={
                            <Button
                                type="button"
                                variant="outline"
                                className="flex-1"
                            />
                        }
                    >
                        {t.common.cancel}
                    </SheetClose>
                    <Button type="button" className="flex-1" onClick={apply}>
                        {t.common.apply}
                    </Button>
                </SheetFooter>
            </SheetContent>
        </Sheet>
    )
}

function SectionTitle({ children }: { children: React.ReactNode }) {
    return <h3 className="m3-title-small text-on-surface">{children}</h3>
}

type DateRangeFieldProps = {
    range: DateRange | undefined
    onSelect: (range: DateRange | undefined) => void
    onClear: () => void
}

function DateRangeField({ range, onSelect, onClear }: DateRangeFieldProps) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const [open, setOpen] = useState(false)
    const label =
        range?.from || range?.to
            ? formatDateRange(range.from, range.to, t, formatLocale)
            : t.activity.selectRange
    return (
        <div className="flex items-center gap-2">
            <Popover open={open} onOpenChange={setOpen}>
                <PopoverTrigger
                    render={
                        <Button
                            type="button"
                            variant="outline"
                            className="flex-1 justify-start font-normal"
                        />
                    }
                >
                    <Icon
                        name="calendar_month"
                        className="text-on-surface-variant"
                    />
                    <span className="truncate">{label}</span>
                </PopoverTrigger>
                <PopoverContent className="w-auto p-0" align="start">
                    <Calendar
                        mode="range"
                        selected={range}
                        onSelect={onSelect}
                        numberOfMonths={1}
                        autoFocus
                    />
                </PopoverContent>
            </Popover>
            {range?.from || range?.to ? (
                <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    aria-label={t.activity.clearRange}
                    onClick={onClear}
                >
                    <Icon name="close" size={20} />
                </Button>
            ) : null}
        </div>
    )
}

type TogglePickerProps = {
    entities: NamedEntity[]
    selected: string[]
    onChange: (next: string[]) => void
    emptyText: string
}

function TogglePicker({
    entities,
    selected,
    onChange,
    emptyText,
}: TogglePickerProps) {
    if (entities.length === 0) {
        return (
            <p className="m3-body-medium text-on-surface-variant">
                {emptyText}
            </p>
        )
    }
    return (
        <div className="flex flex-wrap gap-2">
            {entities.map((entity) => {
                const isSelected = selected.includes(entity.id)
                return (
                    <ChoiceChip
                        key={entity.id}
                        label={entity.name}
                        selected={isSelected}
                        onSelect={() =>
                            onChange(
                                isSelected
                                    ? selected.filter((id) => id !== entity.id)
                                    : [...selected, entity.id],
                            )
                        }
                    />
                )
            })}
        </div>
    )
}

type ActiveFilterChipsProps = FiltersSheetProps

function ActiveFilterChips({
    filters,
    onChange,
    accounts,
    categories,
    tags,
}: ActiveFilterChipsProps) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const chips: { key: string; label: string; onRemove: () => void }[] = []

    if (filters.dateFrom || filters.dateTo) {
        chips.push({
            key: 'date',
            label: formatDateRange(
                filters.dateFrom,
                filters.dateTo,
                t,
                formatLocale,
            ),
            onRemove: () =>
                onChange({
                    ...filters,
                    dateFrom: undefined,
                    dateTo: undefined,
                }),
        })
    }
    if (filters.accountIds.length) {
        chips.push({
            key: 'accounts',
            label: summarizeNames(
                filters.accountIds,
                accounts,
                t.activity.fallbackAccounts,
            ),
            onRemove: () => onChange({ ...filters, accountIds: [] }),
        })
    }
    if (filters.categoryIds.length) {
        chips.push({
            key: 'categories',
            label: summarizeNames(
                filters.categoryIds,
                categories,
                t.activity.fallbackCategories,
            ),
            onRemove: () => onChange({ ...filters, categoryIds: [] }),
        })
    }
    if (filters.tagIds.length) {
        chips.push({
            key: 'tags',
            label: summarizeNames(
                filters.tagIds,
                tags,
                t.activity.fallbackTags,
            ),
            onRemove: () => onChange({ ...filters, tagIds: [] }),
        })
    }

    return (
        <div className="flex gap-2 overflow-x-auto px-4">
            {chips.map((chip) => (
                <InputChip
                    key={chip.key}
                    onRemove={chip.onRemove}
                    removeLabel={t.activity.removeFilter({ label: chip.label })}
                >
                    {chip.label}
                </InputChip>
            ))}
        </div>
    )
}

function summarizeNames(
    ids: string[],
    entities: NamedEntity[],
    fallback: string,
): string {
    const names = ids
        .map((id) => entities.find((e) => e.id === id)?.name)
        .filter((name): name is string => Boolean(name))
    if (names.length === 0) return fallback
    if (names.length <= 2) return names.join(', ')
    return `${names.slice(0, 2).join(', ')} +${names.length - 2}`
}

function formatDateRange(
    from: Date | undefined,
    to: Date | undefined,
    messages: Messages,
    locale: string,
): string {
    const fmt = (d: Date) => formatNumericDate(d, locale)
    if (from && to) return `${fmt(from)} – ${fmt(to)}`
    if (from) return messages.activity.rangeFrom({ date: fmt(from) })
    if (to) return messages.activity.rangeTo({ date: fmt(to) })
    return ''
}
