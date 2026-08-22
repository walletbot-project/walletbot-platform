import { api } from '@wallet-bot/backend/api'
import type { SimpleFilter } from '@wallet-bot/shared'
import { useQuery } from 'convex/react'
import { useState } from 'react'
import { FilterSheet } from '@/components/filters/filter-sheet'
import { datePresetLabel } from '@/components/filters/labels'
import { InputChip } from '@/components/m3/chip'
import { Icon } from '@/components/m3/icon'
import { Input } from '@/components/ui/input'
import { type Messages, useFormatLocale, useT } from '@/lib/i18n'
import {
    activeFilterCount,
    formatNumericDate,
    hasActiveFilters,
} from './helpers'

type NamedEntity = { id: string; name: string }

type TransactionFiltersBarProps = {
    filter: SimpleFilter
    onChange: (next: SimpleFilter) => void
}

/**
 * Search field plus the filter sheet, over the canonical filter. Purely
 * controlled — it never owns the filter, so the list can persist or share it,
 * matching native's `TransactionFiltersBar`.
 */
export function TransactionFiltersBar({
    filter,
    onChange,
}: TransactionFiltersBarProps) {
    const t = useT()
    const [open, setOpen] = useState(false)
    const accounts = useQuery(api.v1.accounts.queries.listActive)
    const categories = useQuery(api.v1.categories.queries.listActive)
    const tags = useQuery(api.v1.tags.queries.listActive)
    const count = activeFilterCount(filter)

    return (
        <div className="flex flex-col gap-2.5">
            <div className="flex items-center gap-2 px-4">
                <div className="relative flex-1">
                    <Icon
                        name="search"
                        filled
                        className="-translate-y-1/2 pointer-events-none absolute top-1/2 left-4 text-on-surface-variant"
                    />
                    <Input
                        value={filter.search ?? ''}
                        onChange={(e) =>
                            onChange({ ...filter, search: e.target.value })
                        }
                        placeholder={t.activity.search}
                        className="h-13 rounded-[32px] border-none bg-surface-container-highest pr-5 pl-13 text-on-surface shadow-none"
                    />
                </div>
                <button
                    type="button"
                    onClick={() => setOpen(true)}
                    className="m3-state-layer relative flex size-10 shrink-0 cursor-pointer items-center justify-center rounded-full bg-secondary-container text-on-secondary-container"
                    aria-label={t.activity.filters}
                >
                    <Icon name="tune" filled />
                    {count > 0 ? (
                        <span className="-top-0.5 -right-0.5 absolute flex min-h-4.5 min-w-4.5 items-center justify-center rounded-[10px] bg-primary px-1.5 font-bold text-[11px] text-on-primary">
                            {count}
                        </span>
                    ) : null}
                </button>
            </div>

            {hasActiveFilters(filter) ? (
                <ActiveFilterChips
                    filter={filter}
                    onChange={onChange}
                    accounts={accounts ?? []}
                    categories={categories ?? []}
                    tags={tags ?? []}
                />
            ) : null}

            <FilterSheet
                open={open}
                onOpenChange={setOpen}
                initial={filter}
                // The bar owns the search field, and the activity list has never
                // offered a pending/cleared switch — native hides exactly these
                // two here, and forces the advanced toggle back on.
                hiddenSections={['text', 'status']}
                allowAdvanced
                onApply={onChange}
            />
        </div>
    )
}

type ActiveFilterChipsProps = {
    filter: SimpleFilter
    onChange: (next: SimpleFilter) => void
    accounts: NamedEntity[]
    categories: NamedEntity[]
    tags: NamedEntity[]
}

function ActiveFilterChips({
    filter,
    onChange,
    accounts,
    categories,
    tags,
}: ActiveFilterChipsProps) {
    const t = useT()
    const formatLocale = useFormatLocale()
    const chips: { key: string; label: string; onRemove: () => void }[] = []

    if (filter.dateFrom || filter.dateTo) {
        chips.push({
            key: 'date',
            label: formatDateRange(
                filter.dateFrom,
                filter.dateTo,
                t,
                formatLocale,
            ),
            onRemove: () =>
                onChange({ ...filter, dateFrom: null, dateTo: null }),
        })
    } else if (filter.datePreset) {
        chips.push({
            key: 'date',
            label: datePresetLabel(filter.datePreset, t),
            onRemove: () => onChange({ ...filter, datePreset: null }),
        })
    }
    if (filter.accountIds.length) {
        chips.push({
            key: 'accounts',
            label: summarizeNames(
                filter.accountIds,
                accounts,
                t.activity.fallbackAccounts,
            ),
            onRemove: () => onChange({ ...filter, accountIds: [] }),
        })
    }
    if (filter.categoryIds.length) {
        chips.push({
            key: 'categories',
            label: summarizeNames(
                filter.categoryIds,
                categories,
                t.activity.fallbackCategories,
            ),
            onRemove: () => onChange({ ...filter, categoryIds: [] }),
        })
    }
    if (filter.tagIds.length) {
        chips.push({
            key: 'tags',
            label: summarizeNames(filter.tagIds, tags, t.activity.fallbackTags),
            onRemove: () => onChange({ ...filter, tagIds: [] }),
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

/** `YYYY-MM-DD` as the user's locale renders it; anything else is left alone. */
function formatDay(iso: string, locale: string): string {
    const [year, month, day] = iso.slice(0, 10).split('-').map(Number)
    if (!year || !month || !day) return iso
    return formatNumericDate(new Date(year, month - 1, day), locale)
}

function formatDateRange(
    from: string | null,
    to: string | null,
    messages: Messages,
    locale: string,
): string {
    if (from && to) {
        return `${formatDay(from, locale)} – ${formatDay(to, locale)}`
    }
    if (from)
        return messages.activity.rangeFrom({ date: formatDay(from, locale) })
    if (to) return messages.activity.rangeTo({ date: formatDay(to, locale) })
    return ''
}
