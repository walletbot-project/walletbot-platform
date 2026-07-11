import { api } from '@wallet-bot/backend/api'
import { usePaginatedQuery } from 'convex/react'
import { Loader2 } from 'lucide-react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useLocation } from 'react-router-dom'
import { Skeleton } from '@/components/ui/skeleton'
import { FilterChips } from './filter-chips'
import {
    buildListEntries,
    dateFromMs,
    dateToMs,
    EMPTY_FILTERS,
    estimatedDescription,
    matchesFilters,
    signedAmountCents,
    type TransactionFilters,
    type TransactionType,
} from './helpers'
import { TransactionFiltersBar } from './transaction-filters-bar'
import { TransactionRow } from './transaction-row'

// How many extra rows to eagerly pull when client-side filters thin out the
// visible page, and the ceiling that stops auto-loading from walking the whole
// table for a filter that matches almost nothing.
const REFILL_THRESHOLD = 25
const AUTO_LOAD_CAP = 1_000
const PAGE_SIZE = 50

export function Activity() {
    // A details sheet can deep-link here with a pre-applied entity filter,
    // passed via the router location state (see the account/category/tag sheets).
    const location = useLocation()
    const [filters, setFilters] = useState<TransactionFilters>(() => {
        const seed = location.state as Partial<TransactionFilters> | null
        if (seed?.accountIds || seed?.categoryIds || seed?.tagIds) {
            return { ...EMPTY_FILTERS, ...seed }
        }
        return EMPTY_FILTERS
    })
    const [type, setType] = useState<TransactionType | null>(null)

    // The backend narrows by a single account/category plus the date range
    // (all index-backed). Everything else is refined client-side below.
    const accountId =
        filters.accountIds.length === 1 ? filters.accountIds[0] : undefined
    const categoryId =
        !accountId && filters.categoryIds.length === 1
            ? filters.categoryIds[0]
            : undefined

    const { results, status, loadMore } = usePaginatedQuery(
        api.v1.transactions.queries.listPaginated,
        {
            accountId,
            categoryId,
            dateFrom: dateFromMs(filters.dateFrom),
            dateTo: dateToMs(filters.dateTo),
            includeTags: filters.tagIds.length > 0,
        },
        { initialNumItems: PAGE_SIZE },
    )

    const filtered = useMemo(
        () => results.filter((t) => matchesFilters(t, filters, type)),
        [results, filters, type],
    )

    // "Now" is captured once via a lazy initializer — reading the clock during
    // the render body is impure, but a one-time mount value is stable.
    const [now] = useState(() => new Date())
    const nowMs = now.getTime()

    const entries = useMemo(
        () => buildListEntries(filtered, nowMs),
        [filtered, nowMs],
    )

    // Keep the list filled when client-side filters reduce the loaded page.
    useEffect(() => {
        if (
            status === 'CanLoadMore' &&
            filtered.length < REFILL_THRESHOLD &&
            results.length < AUTO_LOAD_CAP
        ) {
            loadMore(PAGE_SIZE)
        }
    }, [status, filtered.length, results.length, loadMore])

    // Infinite scroll: load the next page when the sentinel comes into view.
    const sentinelRef = useRef<HTMLDivElement>(null)
    useEffect(() => {
        const el = sentinelRef.current
        if (!el) return
        const observer = new IntersectionObserver((observed) => {
            if (observed[0]?.isIntersecting && status === 'CanLoadMore') {
                loadMore(PAGE_SIZE)
            }
        })
        observer.observe(el)
        return () => observer.disconnect()
    }, [status, loadMore])

    return (
        <div className="flex flex-1 flex-col">
            <div className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-4 p-4">
                <TransactionFiltersBar
                    filters={filters}
                    onChange={setFilters}
                />
                <FilterChips selected={type} onChange={setType} />

                {status === 'LoadingFirstPage' ? (
                    <ListSkeleton />
                ) : entries.length === 0 && status === 'Exhausted' ? (
                    <p className="py-12 text-center text-sm text-muted-foreground">
                        No hay transacciones
                    </p>
                ) : (
                    <div className="flex flex-col gap-2">
                        {entries.map((entry) =>
                            entry.kind === 'header' ? (
                                <h2
                                    key={entry.key}
                                    className="px-1 pt-3 text-sm font-bold text-foreground first:pt-0"
                                >
                                    {entry.label}
                                </h2>
                            ) : (
                                <TransactionRow
                                    key={entry.key}
                                    title={entry.txn.name}
                                    amountCents={signedAmountCents(entry.txn)}
                                    dateConfirmed={entry.txn.dateConfirmed}
                                    description={estimatedDescription(
                                        entry.txn,
                                    )}
                                />
                            ),
                        )}
                    </div>
                )}

                {status === 'LoadingMore' ? (
                    <div className="flex justify-center py-4">
                        <Loader2 className="size-5 animate-spin text-muted-foreground" />
                    </div>
                ) : null}

                <div ref={sentinelRef} aria-hidden className="h-1" />
            </div>
        </div>
    )
}

function ListSkeleton() {
    return (
        <div className="flex flex-col gap-2">
            {Array.from({ length: 6 }).map((_, i) => (
                <Skeleton key={i} className="h-14 w-full rounded-xl" />
            ))}
        </div>
    )
}
