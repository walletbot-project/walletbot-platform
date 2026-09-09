import { defineTable } from 'convex/server'
import { v } from 'convex/values'

export const transactions = defineTable({
    userId: v.string(),
    id: v.string(), // client-side uuid

    type: v.union(
        v.literal('expense'),
        v.literal('income'),
        v.literal('transfer'),
        v.literal('balance_adjustment'),
    ),
    name: v.string(),
    description: v.optional(v.string()),
    status: v.union(v.literal('pending'), v.literal('cleared')),
    date: v.int64(), // ms since epoch
    // Optional during the widen/backfill/narrow rollout. New writes always set
    // it; historical rows are interpreted as `none` until migrated.
    timeStatus: v.optional(
        v.union(
            v.literal('confirmed'),
            v.literal('approximation'),
            v.literal('none'),
        ),
    ),
    accountId: v.string(), // uuid of account
    categoryId: v.string(), // uuid of category
    amount: v.int64(), // cents
    currency: v.string(),

    // Transfers
    toAccountId: v.optional(v.string()),
    toAmount: v.optional(v.int64()),
    toCurrency: v.optional(v.string()),
    exchangeRate: v.optional(v.number()), // float

    // Balance adjustments
    balanceAfter: v.optional(v.int64()), // cents

    // Set on every occurrence a recurring rule materialised; absent on a
    // one-off. `recurrenceIndex` is the occurrence's position in the series
    // (0 is the anchor) — stored rather than derived from the date, so an
    // edit that moves one occurrence cannot renumber the rest.
    recurrenceId: v.optional(v.string()),
    recurrenceIndex: v.optional(v.int64()),

    isArchived: v.boolean(),
    createdAt: v.int64(),
    updatedAt: v.int64(),
    seq: v.int64(),
    dateConfirmed: v.boolean(),
})
    .index('by_user_seq', ['userId', 'seq'])
    .index('by_user_id', ['userId', 'id'])
    .index('by_user_date', ['userId', 'date'])
    .index('by_user_status', ['userId', 'status'])
    .index('by_user_type', ['userId', 'type'])
    // Live rows in calendar order. `by_user_date` cannot serve the upcoming
    // list: archived rows sit in it interleaved with the live ones, so
    // deleting the tail of a series left the paginator walking hundreds of
    // rows it would then discard — near-empty pages, and a "load more" that
    // never reached the end. Every read excludes archived rows, so the
    // dimension belongs in the index rather than in a predicate after it.
    .index('by_user_archived_date', ['userId', 'isArchived', 'date'])
    .index('by_user_account_date', ['userId', 'accountId', 'date'])
    .index('by_user_category_date', ['userId', 'categoryId', 'date'])
    .index('by_user_to_account_date', ['userId', 'toAccountId', 'date'])
    // The series in calendar order: what "this and the ones after it" walks,
    // and where "the last one" is read from when a series is topped up.
    .index('by_user_recurrence_date', ['userId', 'recurrenceId', 'date'])
    // The series in occurrence order. Not redundant with the one above: the
    // materialiser addresses occurrences *by index*, and once an occurrence's
    // date can be edited on its own, index order and date order stop agreeing.
    .index('by_user_recurrence_index', [
        'userId',
        'recurrenceId',
        'recurrenceIndex',
    ])
    // Text search over the user's whole history. Native filters with SQL LIKE
    // against its local database, so a web search that only looked at the rows
    // already paged in silently missed older matches. A search index takes one
    // `searchField` each, and the text dimension covers name *and* description
    // (`matchesCondition`, case 'text'), so it takes two — callers union the
    // candidates. `isArchived` is a filter field because every read excludes
    // archived rows.
    .searchIndex('search_name', {
        searchField: 'name',
        filterFields: ['userId', 'isArchived'],
    })
    .searchIndex('search_description', {
        searchField: 'description',
        filterFields: ['userId', 'isArchived'],
    })
