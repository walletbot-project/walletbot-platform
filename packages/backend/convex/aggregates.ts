import { DirectAggregate, TableAggregate } from '@convex-dev/aggregate'
import { components } from './_generated/api'
import type { DataModel, Doc } from './_generated/dataModel'

// Two aggregates over `transactions` give us O(log n) balance reads:
//
//  - `outflowsByAccount` — signed effect on the *source* account (doc.accountId).
//    Every transaction lives here under namespace `${userId}:${accountId}`.
//
//  - `inflowsByAccount` — credit to the *destination* account for transfers
//    (doc.toAccountId). Non-transfers live in a sentinel namespace and
//    contribute 0, so summing by real account ignores them.
//
// Balance(userId, accountId) =
//   outflowsByAccount.sum(`${userId}:${accountId}`)
// + inflowsByAccount.sum(`${userId}:${accountId}`)

const NONE_NS = '__none__'

function ns(userId: string, accountId: string): string {
    return `${userId}:${accountId}`
}

export function outflowsNamespace(doc: Doc<'transactions'>): string {
    return ns(doc.userId, doc.accountId)
}

export function inflowsNamespace(doc: Doc<'transactions'>): string {
    if (doc.type !== 'transfer' || !doc.toAccountId) return NONE_NS
    return ns(doc.userId, doc.toAccountId)
}

export function outflowsValue(doc: Doc<'transactions'>): number {
    if (doc.isArchived) return 0
    const amount = Number(doc.amount)
    switch (doc.type) {
        case 'expense':
            return -amount
        case 'income':
            return amount
        case 'transfer':
            return -amount
        case 'balance_adjustment':
            return amount
    }
}

export function inflowsValue(doc: Doc<'transactions'>): number {
    if (doc.isArchived) return 0
    if (doc.type !== 'transfer') return 0
    return Number(doc.toAmount ?? doc.amount)
}

export const outflowsByAccount = new TableAggregate<{
    Namespace: string
    Key: bigint
    DataModel: DataModel
    TableName: 'transactions'
}>(components.outflowsByAccount, {
    namespace: outflowsNamespace,
    sortKey: (doc) => doc.date,
    sumValue: outflowsValue,
})

export const inflowsByAccount = new TableAggregate<{
    Namespace: string
    Key: bigint
    DataModel: DataModel
    TableName: 'transactions'
}>(components.inflowsByAccount, {
    namespace: inflowsNamespace,
    sortKey: (doc) => doc.date,
    sumValue: inflowsValue,
})

export function accountNamespace(userId: string, accountId: string): string {
    return ns(userId, accountId)
}

// Tag usage. The join row carries no date, so this is a DirectAggregate fed
// by the join and transaction write paths (see tags/helpers.ts): an entry
// exists for a join exactly while its transaction exists and is not archived,
// keyed by that transaction's date. Namespace `${userId}:${tagId}`.
export function tagNamespace(userId: string, tagId: string): string {
    return ns(userId, tagId)
}

export const transactionsByTag = new DirectAggregate<{
    Namespace: string
    Key: bigint
    Id: string
}>(components.transactionsByTag)
