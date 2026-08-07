import { api } from '@wallet-bot/backend/api'
import { useQuery } from 'convex/react'
import { CalendarDays, Search, SlidersHorizontal, X } from 'lucide-react'
import { useState } from 'react'
import type { DateRange } from 'react-day-picker'
import { Badge } from '@/components/ui/badge'
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
import { cn } from '@/lib/utils'
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
        <div className="flex flex-col gap-3">
            <div className="flex items-center gap-2">
                <div className="relative flex-1">
                    <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                    <Input
                        value={filters.search}
                        onChange={(e) =>
                            onChange({ ...filters, search: e.target.value })
                        }
                        placeholder={t.activity.search}
                        className="rounded-full pl-9"
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
                    <Button
                        type="button"
                        variant="outline"
                        size="icon"
                        className="relative shrink-0"
                        aria-label={t.activity.filters}
                    />
                }
            >
                <SlidersHorizontal />
                {count > 0 ? (
                    <span className="absolute -top-1.5 -right-1.5 flex size-4 items-center justify-center rounded-full bg-primary text-[10px] font-bold text-primary-foreground">
                        {count}
                    </span>
                ) : null}
            </SheetTrigger>
            <SheetContent side="right" className="w-full gap-0 sm:max-w-md">
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
    return <h3 className="text-sm font-semibold text-foreground">{children}</h3>
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
                    <CalendarDays className="text-muted-foreground" />
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
                    <X />
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
        return <p className="text-sm text-muted-foreground">{emptyText}</p>
    }
    return (
        <div className="flex flex-wrap gap-2">
            {entities.map((entity) => {
                const isSelected = selected.includes(entity.id)
                return (
                    <Button
                        key={entity.id}
                        type="button"
                        size="sm"
                        variant={isSelected ? 'secondary' : 'outline'}
                        className={cn(
                            'rounded-full',
                            isSelected && 'border-primary',
                        )}
                        onClick={() =>
                            onChange(
                                isSelected
                                    ? selected.filter((id) => id !== entity.id)
                                    : [...selected, entity.id],
                            )
                        }
                    >
                        {entity.name}
                    </Button>
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
        <div className="flex flex-wrap gap-2">
            {chips.map((chip) => (
                <Badge
                    key={chip.key}
                    variant="secondary"
                    className="gap-1 py-1 pr-1 pl-2.5"
                >
                    {chip.label}
                    <button
                        type="button"
                        aria-label={t.activity.removeFilter({
                            label: chip.label,
                        })}
                        onClick={chip.onRemove}
                        className="rounded-full p-0.5 hover:bg-foreground/10"
                    >
                        <X className="size-3" />
                    </button>
                </Badge>
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
