import { TextField } from 'actify'
import { type ReactNode, useMemo, useState } from 'react'
import { useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'
import { BottomSheet } from './bottom-sheet'
import { ChoiceChip } from './chip'
import { Icon } from './icon'

export type SheetOption = {
    id: string
    label: string
    /** Second line, e.g. an account's currency. */
    supporting?: string
    leading?: ReactNode
}

type OptionSheetProps = {
    open: boolean
    onOpenChange: (open: boolean) => void
    title: string
    options: readonly SheetOption[]
    /** The currently chosen id, or null when nothing is selected. */
    selected: string | null
    onSelect: (id: string) => void
    /** Renders a search box above the list once there are enough options. */
    searchPlaceholder?: string
    /** Quick picks shown as chips above the list while the search is empty. */
    suggested?: readonly string[]
    /** Extra action pinned above the list, e.g. "clear selection". */
    header?: ReactNode
    emptyMessage?: string
}

/** Below this many options the search box is noise rather than help. */
const SEARCH_THRESHOLD = 8

/**
 * The list-of-options bottom sheet the native app opens for account, category,
 * tag and currency selection (`showModalBottomSheet` + a `ListView` of
 * `ListTile`s — see `CurrencyPicker` and the transaction form's pickers).
 */
export function OptionSheet({
    open,
    onOpenChange,
    title,
    options,
    selected,
    onSelect,
    searchPlaceholder,
    suggested,
    header,
    emptyMessage,
}: OptionSheetProps) {
    const t = useT()
    const [query, setQuery] = useState('')

    // Start every presentation with a clean search. The sheet is controlled by
    // the `open` prop (there is no Base UI trigger), so `onOpenChange(true)`
    // never fires — adjust on the prop flip, during render.
    const [wasOpen, setWasOpen] = useState(open)
    if (wasOpen !== open) {
        setWasOpen(open)
        if (open) setQuery('')
    }

    const filtered = useMemo(() => {
        const trimmed = query.trim().toLowerCase()
        if (!trimmed) return options
        return options.filter(
            (option) =>
                option.label.toLowerCase().includes(trimmed) ||
                option.supporting?.toLowerCase().includes(trimmed),
        )
    }, [options, query])

    const showSearch =
        searchPlaceholder !== undefined && options.length >= SEARCH_THRESHOLD

    return (
        <BottomSheet
            open={open}
            onOpenChange={onOpenChange}
            title={title}
            showTitle
        >
            <div className="flex flex-col gap-3 px-4 pb-6">
                {showSearch ? (
                    <TextField
                        aria-label={searchPlaceholder}
                        variant="outlined"
                        className="w-full"
                        value={query}
                        onChange={setQuery}
                        placeholder={searchPlaceholder}
                        leadingIcon={
                            <Icon
                                name="search"
                                size={20}
                                className="text-on-surface-variant"
                            />
                        }
                    />
                ) : null}

                {suggested && suggested.length > 0 && query.trim() === '' ? (
                    <div className="flex flex-wrap gap-2">
                        {suggested.map((id) => (
                            <ChoiceChip
                                key={id}
                                label={
                                    options.find((o) => o.id === id)?.label ??
                                    id
                                }
                                selected={selected === id}
                                onSelect={() => onSelect(id)}
                            />
                        ))}
                    </div>
                ) : null}

                {header}

                {filtered.length === 0 ? (
                    <p className="m3-body-medium px-2 py-6 text-center text-on-surface-variant">
                        {emptyMessage ?? t.common.noResults}
                    </p>
                ) : (
                    <ul className="flex flex-col">
                        {filtered.map((option) => {
                            const isSelected = option.id === selected
                            return (
                                <li key={option.id}>
                                    <button
                                        type="button"
                                        onClick={() => onSelect(option.id)}
                                        className={cn(
                                            'm3-state-layer flex w-full cursor-pointer items-center gap-4 rounded-2xl px-3 py-3 text-left',
                                            isSelected
                                                ? 'text-primary'
                                                : 'text-on-surface',
                                        )}
                                    >
                                        {option.leading}
                                        <span className="flex min-w-0 flex-1 flex-col">
                                            <span className="m3-body-large truncate">
                                                {option.label}
                                            </span>
                                            {option.supporting ? (
                                                <span className="m3-body-small truncate text-on-surface-variant">
                                                    {option.supporting}
                                                </span>
                                            ) : null}
                                        </span>
                                        {isSelected ? (
                                            <Icon
                                                name="check_circle"
                                                filled
                                                className="shrink-0 text-primary"
                                            />
                                        ) : null}
                                    </button>
                                </li>
                            )
                        })}
                    </ul>
                )}
            </div>
        </BottomSheet>
    )
}
