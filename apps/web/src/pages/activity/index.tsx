import { api } from '@wallet-bot/backend/api'
import { CircularProgress, IconButton } from 'actify'
import { usePaginatedQuery, useQuery } from 'convex/react'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
    useLocation,
    useNavigate,
    useOutletContext,
    useParams,
    useSearchParams,
} from 'react-router-dom'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
import { ListDetailLayout } from '@/components/m3/list-detail-layout'
import { StateMessage } from '@/components/m3/state-message'
import { Skeleton } from '@/components/ui/skeleton'
import {
    ACCOUNT_DEFAULT_COLOR,
    CATEGORY_DEFAULT_COLOR,
    normalizeColor,
} from '@/lib/entity-colors'
import { useFormatLocale, useT } from '@/lib/i18n'
import { TransactionForm } from '@/pages/add-manual'
import { FilterChips } from './filter-chips'
import {
    buildListEntries,
    dateFromMs,
    dateToMs,
    EMPTY_FILTERS,
    estimatedDescription,
    formatTransactionTime,
    matchesFilters,
    type TransactionFilters,
    type TransactionTransferSide,
    type TransactionType,
    transactionTimeStatus,
} from './helpers'
import { TransactionDetail } from './transaction-detail'
import { TransactionFiltersBar } from './transaction-filters-bar'
import { TransactionRow } from './transaction-row'

// How many extra rows to eagerly pull when client-side filters thin out the
// visible page, and the ceiling that stops auto-loading from walking the whole
// table for a filter that matches almost nothing.
const REFILL_THRESHOLD = 25
const AUTO_LOAD_CAP = 1_000
const PAGE_SIZE = 50

export function Activity() {
    // A details view can deep-link here with a pre-applied entity filter,
    // passed via the router location state (see the account/category/tag details).
    const location = useLocation()
    const t = useT()
    const formatLocale = useFormatLocale()
    const [filters, setFilters] = useState<TransactionFilters>(() => {
        const seed = location.state as Partial<TransactionFilters> | null
        if (
            seed?.accountIds ||
            seed?.categoryIds ||
            seed?.tagIds ||
            seed?.dateFrom ||
            seed?.dateTo
        ) {
            return { ...EMPTY_FILTERS, ...seed }
        }
        return EMPTY_FILTERS
    })
    const [type, setType] = useState<TransactionType | null>(null)
    const navigate = useNavigate()

    // What is open beside the list is the child route's business, not this
    // component's — see `ListDetailLayout`. Opening one is a navigation.
    const openCreate = () => navigate('/activity/new')
    const openDetail = (next: {
        id: string
        transferSide?: TransactionTransferSide
    }) =>
        navigate(
            next.transferSide
                ? `/activity/${next.id}?side=${next.transferSide}`
                : `/activity/${next.id}`,
        )
    const accounts = useQuery(api.v1.accounts.queries.list, {
        includeArchived: true,
    })
    const categories = useQuery(api.v1.categories.queries.listActive)

    const accountsById = useMemo(
        () => new Map((accounts ?? []).map((account) => [account.id, account])),
        [accounts],
    )
    const categoriesById = useMemo(
        () =>
            new Map(
                (categories ?? []).map((category) => [category.id, category]),
            ),
        [categories],
    )

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
        () => buildListEntries(filtered, nowMs, t, formatLocale),
        [filtered, nowMs, t, formatLocale],
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

    const list = (
        <>
            <AppBar
                title={t.nav.activity}
                actions={
                    <IconButton
                        aria-label={t.activity.addTransaction}
                        onPress={openCreate}
                        className="text-on-surface-variant"
                    >
                        <Icon name="add" />
                    </IconButton>
                }
            />
            <div className="min-h-0 flex-1 overflow-y-auto">
                <div className="flex flex-col gap-4 pt-2 pb-20">
                    <TransactionFiltersBar
                        filters={filters}
                        onChange={setFilters}
                    />
                    <FilterChips selected={type} onChange={setType} />

                    {status === 'LoadingFirstPage' ? (
                        <ListSkeleton />
                    ) : entries.length === 0 && status === 'Exhausted' ? (
                        <p className="m3-body-large py-12 text-center text-on-surface-variant">
                            {t.activity.noTransactions}
                        </p>
                    ) : (
                        <div className="flex flex-col gap-2.5 px-4">
                            {entries.map((entry) =>
                                entry.kind === 'header' ? (
                                    <h2
                                        key={entry.key}
                                        className="pt-2 text-base font-bold first:pt-0"
                                    >
                                        {entry.label}
                                    </h2>
                                ) : (
                                    <TransactionRow
                                        key={entry.key}
                                        title={entry.title}
                                        amountCents={entry.amountCents}
                                        currency={entry.currency}
                                        dateConfirmed={entry.txn.dateConfirmed}
                                        timeLabel={formatTransactionTime(
                                            entry.txn.date,
                                            formatLocale,
                                        )}
                                        timeStatus={transactionTimeStatus(
                                            entry.txn,
                                        )}
                                        description={estimatedDescription(
                                            entry.txn,
                                            t,
                                            formatLocale,
                                        )}
                                        identities={[
                                            ...(accountsById.has(
                                                entry.accountId,
                                            )
                                                ? [
                                                      {
                                                          type: 'account' as const,
                                                          label: t.activity.accountIdentity(
                                                              {
                                                                  name: accountsById.get(
                                                                      entry.accountId,
                                                                  )!.name,
                                                              },
                                                          ),
                                                          icon: accountsById.get(
                                                              entry.accountId,
                                                          )!.icon,
                                                          color: normalizeColor(
                                                              accountsById.get(
                                                                  entry.accountId,
                                                              )!.color,
                                                              ACCOUNT_DEFAULT_COLOR,
                                                          ),
                                                      },
                                                  ]
                                                : []),
                                            ...(categoriesById.has(
                                                entry.txn.categoryId,
                                            )
                                                ? [
                                                      {
                                                          type: 'category' as const,
                                                          label: t.activity.categoryIdentity(
                                                              {
                                                                  name: categoriesById.get(
                                                                      entry.txn
                                                                          .categoryId,
                                                                  )!.name,
                                                              },
                                                          ),
                                                          icon: categoriesById.get(
                                                              entry.txn
                                                                  .categoryId,
                                                          )!.icon,
                                                          color: normalizeColor(
                                                              categoriesById.get(
                                                                  entry.txn
                                                                      .categoryId,
                                                              )!.color,
                                                              CATEGORY_DEFAULT_COLOR,
                                                          ),
                                                      },
                                                  ]
                                                : []),
                                        ]}
                                        onClick={() =>
                                            openDetail({
                                                id: entry.txn.id,
                                                transferSide:
                                                    entry.transferSide,
                                            })
                                        }
                                    />
                                ),
                            )}
                        </div>
                    )}

                    {status === 'LoadingMore' ? (
                        <div className="flex justify-center py-6">
                            <CircularProgress isIndeterminate />
                        </div>
                    ) : null}

                    <div ref={sentinelRef} aria-hidden className="h-1" />
                </div>
            </div>
        </>
    )

    const applyFilter = useCallback(
        (next: Partial<TransactionFilters>) =>
            setFilters({ ...EMPTY_FILTERS, ...next }),
        [],
    )
    const outletContext: ActivityOutletContext = useMemo(
        () => ({ applyFilter }),
        [applyFilter],
    )

    return (
        <ListDetailLayout
            list={list}
            closeTo="/activity"
            detailTitle={t.transaction.detail}
            context={outletContext}
            placeholder={
                <div className="flex flex-1 items-center justify-center p-8">
                    <p className="m3-body-large max-w-xs text-center text-on-surface-variant">
                        {t.activity.selectDetail}
                    </p>
                </div>
            }
        />
    )
}

/** What the Activity list offers its child routes. */
export type ActivityOutletContext = {
    applyFilter: (filters: Partial<TransactionFilters>) => void
}

/** `/activity/new` — the transaction form as the layout's occupant. */
export function TransactionCreateRoute() {
    const navigate = useNavigate()
    // The list is query-driven, so a saved transaction shows up on its own.
    const close = () => navigate('/activity')
    return <TransactionForm onClose={close} onSaved={close} />
}

/** `/activity/:transactionId` — one transaction's detail. */
export function TransactionDetailRoute() {
    const t = useT()
    const navigate = useNavigate()
    const { transactionId } = useParams()
    const [searchParams] = useSearchParams()
    const { applyFilter } = useOutletContext<ActivityOutletContext>()

    const rawSide = searchParams.get('side')
    const transferSide: TransactionTransferSide | undefined =
        rawSide === 'source' || rawSide === 'destination' ? rawSide : undefined

    if (transactionId === undefined) {
        return (
            <StateMessage
                icon="search_off"
                tone="error"
                title={t.common.notFoundTitle}
                detail={t.common.notFoundDescription}
            />
        )
    }

    return (
        <TransactionDetail
            transactionId={transactionId}
            transferSide={transferSide}
            onApplyFilter={(next) => {
                applyFilter(next)
                navigate('/activity')
            }}
            onClose={() => navigate('/activity')}
        />
    )
}

function ListSkeleton() {
    return (
        <div className="flex flex-col gap-2.5 px-4">
            {Array.from({ length: 6 }).map((_, i) => (
                <Skeleton key={i} className="h-20 w-full rounded-xl" />
            ))}
        </div>
    )
}
