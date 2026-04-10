/**
 * Combobox — Multi-select / single-select with virtual scrolling + infinite scroll.
 *
 * Built on base-ui Popover + @tanstack/react-virtual.
 */

import { useVirtualizer } from '@tanstack/react-virtual'
import { Check, ChevronDown, Loader2, Search, X } from 'lucide-react'
import {
    type ReactNode,
    memo,
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from 'react'
import { cn } from '@/lib/utils'
import { Button } from './button'
import { Checkbox } from './checkbox'
import {
    Popover,
    PopoverContent,
    PopoverTrigger,
} from './popover'

// ─── Types ───────────────────────────────────────────────────────────────────

export interface ComboboxOption {
    value: string
    label: string
}

export interface ComboboxProps<T extends ComboboxOption = ComboboxOption> {
    /** Selected values (always an array, even for single select). */
    value: string[]
    /** Called when selection changes. */
    onChange: (value: string[]) => void
    /** Enable multi-select. Default false. */
    multiple?: boolean

    /** Static option list. Provide this OR use onSearch + loadMore for async. */
    options?: T[]
    /** Called when the user types in the search input (for server-side search). */
    onSearch?: (query: string) => void
    /** Called to load more options (infinite scroll). */
    loadMore?: () => void
    /** Whether more options can be loaded. */
    canLoadMore?: boolean
    /** Whether options are currently loading. */
    isLoading?: boolean

    /** Trigger placeholder when nothing is selected. */
    placeholder?: string
    /** Search input placeholder. */
    searchPlaceholder?: string
    /** Message shown when no options match. */
    emptyMessage?: string
    /** Disable the combobox. */
    disabled?: boolean

    /** Custom option renderer. */
    renderOption?: (option: T, state: { isSelected: boolean }) => ReactNode
    /** Custom trigger renderer. Must return a React element (not null). */
    renderTrigger?: (props: {
        selectedOptions: T[]
        open: boolean
    }) => React.ReactElement
    /** Client-side filter function. Ignored when onSearch is provided. */
    filterOption?: (option: T, search: string) => boolean
    /** Additional class name applied to the trigger button. */
    className?: string
}

// ─── Constants ───────────────────────────────────────────────────────────────

const OPTION_HEIGHT = 36
const OVERSCAN = 5
const DEBOUNCE_MS = 300

// ─── Component ───────────────────────────────────────────────────────────────

function ComboboxInner<T extends ComboboxOption>({
    value,
    onChange,
    multiple = false,
    options = [],
    onSearch,
    loadMore,
    canLoadMore,
    isLoading,
    placeholder = 'Select...',
    searchPlaceholder = 'Search...',
    emptyMessage = 'No results',
    disabled = false,
    renderOption,
    renderTrigger,
    filterOption,
    className,
}: ComboboxProps<T>) {
    const [open, setOpen] = useState(false)
    const [searchValue, setSearchValue] = useState('')
    const [highlightedIndex, setHighlightedIndex] = useState(-1)

    const listRef = useRef<HTMLDivElement>(null)
    const inputRef = useRef<HTMLInputElement>(null)
    const sentinelRef = useRef<HTMLDivElement>(null)
    const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)

    // ── Filtering ────────────────────────────────────────────────────────────

    const defaultFilter = useCallback(
        (option: T, search: string) =>
            option.label.toLowerCase().includes(search.toLowerCase()),
        [],
    )

    const filteredOptions = useMemo(() => {
        // When onSearch is provided, the backend handles filtering
        if (onSearch) return options
        if (!searchValue) return options
        const fn = filterOption ?? defaultFilter
        return options.filter((o) => fn(o, searchValue))
    }, [options, searchValue, onSearch, filterOption, defaultFilter])

    // ── Virtual scroll ───────────────────────────────────────────────────────

    const virtualizer = useVirtualizer({
        count: filteredOptions.length,
        getScrollElement: () => listRef.current,
        estimateSize: () => OPTION_HEIGHT,
        overscan: OVERSCAN,
    })

    // The popover content mounts asynchronously, so listRef is null on the
    // first render after open. Force a re-measure once the DOM is ready.
    useEffect(() => {
        if (open) {
            requestAnimationFrame(() => virtualizer.measure())
        }
    }, [open, virtualizer])

    // ── Infinite scroll ──────────────────────────────────────────────────────

    useEffect(() => {
        const sentinel = sentinelRef.current
        const scrollEl = listRef.current
        if (!sentinel || !loadMore || !open) return

        const observer = new IntersectionObserver(
            ([entry]) => {
                if (entry?.isIntersecting && canLoadMore && !isLoading) {
                    loadMore()
                }
            },
            { threshold: 0.1, root: scrollEl },
        )

        observer.observe(sentinel)
        return () => observer.disconnect()
    }, [loadMore, canLoadMore, isLoading, open])

    // ── Search debounce ──────────────────────────────────────────────────────

    const handleSearchChange = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            const v = e.target.value
            setSearchValue(v)
            setHighlightedIndex(-1)

            if (onSearch) {
                if (debounceRef.current) clearTimeout(debounceRef.current)
                debounceRef.current = setTimeout(() => onSearch(v), DEBOUNCE_MS)
            }
        },
        [onSearch],
    )

    // ── Selection ────────────────────────────────────────────────────────────

    const selectedSet = useMemo(() => new Set(value), [value])

    const handleSelect = useCallback(
        (optionValue: string) => {
            if (multiple) {
                const next = selectedSet.has(optionValue)
                    ? value.filter((v) => v !== optionValue)
                    : [...value, optionValue]
                onChange(next)
            } else {
                if (selectedSet.has(optionValue)) {
                    onChange([])
                } else {
                    onChange([optionValue])
                }
                setOpen(false)
            }
        },
        [multiple, selectedSet, value, onChange],
    )

    // ── Keyboard ─────────────────────────────────────────────────────────────

    const handleKeyDown = useCallback(
        (e: React.KeyboardEvent) => {
            const count = filteredOptions.length
            if (count === 0) return

            switch (e.key) {
                case 'ArrowDown': {
                    e.preventDefault()
                    const next =
                        highlightedIndex < count - 1
                            ? highlightedIndex + 1
                            : 0
                    setHighlightedIndex(next)
                    virtualizer.scrollToIndex(next, { align: 'auto' })
                    break
                }
                case 'ArrowUp': {
                    e.preventDefault()
                    const next =
                        highlightedIndex > 0
                            ? highlightedIndex - 1
                            : count - 1
                    setHighlightedIndex(next)
                    virtualizer.scrollToIndex(next, { align: 'auto' })
                    break
                }
                case 'Home': {
                    e.preventDefault()
                    setHighlightedIndex(0)
                    virtualizer.scrollToIndex(0, { align: 'start' })
                    break
                }
                case 'End': {
                    e.preventDefault()
                    setHighlightedIndex(count - 1)
                    virtualizer.scrollToIndex(count - 1, { align: 'end' })
                    break
                }
                case 'Enter': {
                    e.preventDefault()
                    if (
                        highlightedIndex >= 0 &&
                        highlightedIndex < count
                    ) {
                        const opt = filteredOptions[highlightedIndex]
                        if (opt) handleSelect(opt.value)
                    }
                    break
                }
                case 'Escape': {
                    e.preventDefault()
                    setOpen(false)
                    break
                }
            }
        },
        [filteredOptions, highlightedIndex, virtualizer, handleSelect],
    )

    // ── Open/close effects ───────────────────────────────────────────────────

    const handleOpenChange = useCallback(
        (nextOpen: boolean) => {
            setOpen(nextOpen)
            if (nextOpen) {
                setSearchValue('')
                setHighlightedIndex(-1)
                if (onSearch) onSearch('')
                requestAnimationFrame(() => inputRef.current?.focus())
            } else {
                if (debounceRef.current) clearTimeout(debounceRef.current)
            }
        },
        [onSearch],
    )

    // ── Resolve selected options for trigger display ─────────────────────────

    const selectedOptions = useMemo(
        () => options.filter((o) => selectedSet.has(o.value)),
        [options, selectedSet],
    )

    // ── Render ───────────────────────────────────────────────────────────────

    const virtualItems = virtualizer.getVirtualItems()
    const totalSize = virtualizer.getTotalSize()

    return (
        <Popover open={open} onOpenChange={handleOpenChange}>
            <PopoverTrigger
                render={
                    renderTrigger ? (
                        renderTrigger({ selectedOptions, open })
                    ) : (
                        <Button
                            variant="outline"
                            size="sm"
                            disabled={disabled}
                            className={cn("h-8 gap-1.5 justify-between min-w-40", className)}
                        >
                            <span className="truncate text-left flex-1">
                                {selectedOptions.length === 0
                                    ? placeholder
                                    : multiple
                                      ? `${selectedOptions.length} selected`
                                      : selectedOptions[0]?.label}
                            </span>
                            <ChevronDown className="size-3.5 opacity-50 shrink-0" />
                        </Button>
                    )
                }
            />
            <PopoverContent
                className="w-[var(--anchor-width)] min-w-[200px] max-h-(--available-height,300px) flex flex-col p-0 gap-0"
                align="start"
            >
                {/* Search input */}
                <div className="flex items-center border-b border-border px-2 shrink-0">
                    <Search className="size-3.5 shrink-0 text-muted-foreground" />
                    <input
                        ref={inputRef}
                        value={searchValue}
                        onChange={handleSearchChange}
                        onKeyDown={handleKeyDown}
                        placeholder={searchPlaceholder}
                        className="flex-1 bg-transparent py-2 px-2 text-sm outline-none placeholder:text-muted-foreground"
                    />
                    {searchValue && (
                        <button
                            type="button"
                            className="shrink-0 text-muted-foreground hover:text-foreground"
                            onClick={() => {
                                setSearchValue('')
                                setHighlightedIndex(-1)
                                if (onSearch) onSearch('')
                                inputRef.current?.focus()
                            }}
                        >
                            <X className="size-3.5" />
                        </button>
                    )}
                </div>

                {/* Option list */}
                <div
                    ref={listRef}
                    className="flex-1 min-h-0 overflow-y-auto"
                    role="listbox"
                    aria-multiselectable={multiple}
                >
                    {filteredOptions.length === 0 && !isLoading ? (
                        <div className="py-6 text-center text-sm text-muted-foreground">
                            {emptyMessage}
                        </div>
                    ) : (
                        <div
                            style={{
                                position: 'relative',
                                height: totalSize,
                            }}
                        >
                            {virtualItems.map((vItem) => {
                                const option = filteredOptions[vItem.index]
                                if (!option) return null
                                const isSelected = selectedSet.has(
                                    option.value,
                                )
                                const isHighlighted =
                                    highlightedIndex === vItem.index

                                return (
                                    <div
                                        key={option.value}
                                        role="option"
                                        aria-selected={isSelected}
                                        style={{
                                            position: 'absolute',
                                            top: vItem.start,
                                            width: '100%',
                                            height: OPTION_HEIGHT,
                                        }}
                                        className={cn(
                                            'flex items-center gap-2 px-2 cursor-pointer select-none text-sm last:rounded-b-md',
                                            isHighlighted &&
                                                'bg-accent text-accent-foreground',
                                            !isHighlighted &&
                                                'hover:bg-accent/50',
                                        )}
                                        onClick={() =>
                                            handleSelect(option.value)
                                        }
                                        onMouseEnter={() =>
                                            setHighlightedIndex(vItem.index)
                                        }
                                    >
                                        {renderOption ? (
                                            renderOption(option, {
                                                isSelected,
                                            })
                                        ) : (
                                            <>
                                                {multiple ? (
                                                    <Checkbox
                                                        checked={isSelected}
                                                        tabIndex={-1}
                                                        aria-hidden
                                                        className="pointer-events-none"
                                                    />
                                                ) : (
                                                    <Check
                                                        className={cn(
                                                            'size-4 shrink-0',
                                                            isSelected
                                                                ? 'opacity-100'
                                                                : 'opacity-0',
                                                        )}
                                                    />
                                                )}
                                                <span className="truncate">
                                                    {option.label}
                                                </span>
                                            </>
                                        )}
                                    </div>
                                )
                            })}
                        </div>
                    )}

                    {/* Infinite scroll sentinel */}
                    <div ref={sentinelRef} className="h-px" />

                    {/* Loading indicator */}
                    {isLoading && (
                        <div className="flex items-center justify-center py-2">
                            <Loader2 className="size-4 animate-spin text-muted-foreground" />
                        </div>
                    )}
                </div>
            </PopoverContent>
        </Popover>
    )
}

export const Combobox = memo(ComboboxInner) as typeof ComboboxInner
