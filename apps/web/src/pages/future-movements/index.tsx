import { api } from '@wallet-bot/backend/api'
import { CircularProgress, IconButton } from 'actify'
import { usePaginatedQuery, useQuery } from 'convex/react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useOutletContext, useParams } from 'react-router-dom'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
import { ListDetailLayout } from '@/components/m3/list-detail-layout'
import { StateMessage } from '@/components/m3/state-message'
import { Skeleton } from '@/components/ui/skeleton'
import { useOccurrenceCutoff } from '@/hooks/use-occurrence-cutoff'
import {
    ACCOUNT_DEFAULT_COLOR,
    CATEGORY_DEFAULT_COLOR,
    normalizeColor,
} from '@/lib/entity-colors'
import { useFormatLocale, useT } from '@/lib/i18n'
import {
    type ActivityTransaction,
    estimatedDescription,
    formatTransactionTime,
    transactionTimeStatus,
} from '../activity/helpers'
import { TransactionRow } from '../activity/transaction-row'
import { FutureMovementDetail } from './detail'
import { buildFutureEntries, identitiesFor } from './helpers'

const PAGE_SIZE = 50

/**
 * The upcoming side of Activity: the movements that exist but have not
 * happened yet.
 *
 * There is nothing special about the rows — they are ordinary transactions
 * whose date is past the occurrence cutoff, which is exactly why every read on
 * the other side of that cutoff has to exclude them. The user is never told a
 * filter is involved; there are simply two lists, one behind and one ahead.
 *
 * Structurally this is the Activity list: the same `ListDetailLayout`, the
 * same `TransactionRow`, the same day headers. It runs ascending, because the
 * soonest movement is the interesting one.
 */
export function FutureMovements() {
    const t = useT()
    const locale = useFormatLocale()
    const navigate = useNavigate()
    const asOfMs = useOccurrenceCutoff()

    const { results, status, loadMore } = usePaginatedQuery(
        api.v1.transactions.queries.listUpcoming,
        { asOfMs },
        { initialNumItems: PAGE_SIZE },
    )

    const accounts = useQuery(api.v1.accounts.queries.list, {
        includeArchived: true,
    })
    const categories = useQuery(api.v1.categories.queries.listActive)

    const accountsById = useMemo(
        () =>
            new Map(
                (accounts ?? []).map((account) => [
                    account.id,
                    {
                        ...account,
                        color: normalizeColor(
                            account.color,
                            ACCOUNT_DEFAULT_COLOR,
                        ),
                    },
                ]),
            ),
        [accounts],
    )
    const categoriesById = useMemo(
        () =>
            new Map(
                (categories ?? []).map((category) => [
                    category.id,
                    {
                        ...category,
                        color: normalizeColor(
                            category.color,
                            CATEGORY_DEFAULT_COLOR,
                        ),
                    },
                ]),
            ),
        [categories],
    )

    // "Now" is captured once via a lazy initializer, as in Activity: reading
    // the clock during render is impure, but a one-time mount value is stable.
    const [nowMs] = useState(() => Date.now())
    const entries = useMemo(
        () => buildFutureEntries(results, nowMs, t, locale),
        [results, nowMs, t, locale],
    )

    // Infinite scroll, the same sentinel Activity uses.
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
                title={t.futureMovements.title}
                leading={
                    <IconButton
                        aria-label={t.common.goBack}
                        onPress={() => navigate(-1)}
                        className="text-on-surface-variant"
                    >
                        <Icon name="arrow_back" />
                    </IconButton>
                }
            />
            <div className="min-h-0 flex-1 overflow-y-auto">
                <div className="flex flex-col gap-4 pt-2 pb-20">
                    <div className="mx-4 flex items-start gap-3 rounded-xl bg-secondary-container px-4 py-3 text-on-secondary-container">
                        <Icon
                            name="info"
                            size={20}
                            className="mt-0.5 shrink-0"
                        />
                        <p className="m3-body-medium">
                            {t.futureMovements.info}
                        </p>
                    </div>

                    {status === 'LoadingFirstPage' ? (
                        <ListSkeleton />
                    ) : entries.length === 0 ? (
                        <p className="m3-body-large py-12 text-center text-on-surface-variant">
                            {t.futureMovements.empty}
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
                                        title={entry.txn.name}
                                        amountCents={entry.amountCents}
                                        currency={entry.txn.currency}
                                        dateConfirmed={entry.txn.dateConfirmed}
                                        timeLabel={formatTransactionTime(
                                            entry.txn.date,
                                            locale,
                                        )}
                                        timeStatus={transactionTimeStatus(
                                            entry.txn,
                                        )}
                                        description={estimatedDescription(
                                            entry.txn,
                                            t,
                                            locale,
                                        )}
                                        identities={identitiesFor(
                                            entry.txn,
                                            t,
                                            accountsById,
                                            categoriesById,
                                        )}
                                        onClick={() =>
                                            navigate(
                                                `/future-movements/${entry.txn.id}`,
                                            )
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

    const outletContext: FutureMovementsOutletContext = useMemo(
        () => ({ movements: results }),
        [results],
    )

    return (
        <ListDetailLayout
            list={list}
            closeTo="/future-movements"
            detailTitle={t.futureMovements.detail}
            context={outletContext}
            placeholder={
                <div className="flex flex-1 items-center justify-center p-8">
                    <p className="m3-body-large max-w-xs text-center text-on-surface-variant">
                        {t.futureMovements.selectDetail}
                    </p>
                </div>
            }
        />
    )
}

/**
 * What the list offers its child route. The detail reads the movement out of
 * the page the list already holds rather than re-querying by id, because the
 * list is the only thing that knows which page an upcoming movement is on.
 */
export type FutureMovementsOutletContext = {
    movements: readonly ActivityTransaction[]
}

/** `/future-movements/:movementId` — one upcoming movement's detail. */
export function FutureMovementDetailRoute() {
    const t = useT()
    const navigate = useNavigate()
    const { movementId } = useParams()
    const { movements } = useOutletContext<FutureMovementsOutletContext>()

    const movement = movements.find((m) => m.id === movementId) ?? null

    if (!movement) {
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
        <FutureMovementDetail
            // Keyed so opening a different movement gets a fresh form rather
            // than one still holding the previous occurrence's edits.
            key={movement.id}
            movement={movement}
            onClose={() => navigate('/future-movements')}
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
