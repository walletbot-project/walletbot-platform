import type { Messages } from '@/lib/i18n'
import {
    type ActivityTransaction,
    sectionLabel,
    signedAmountCents,
} from '../activity/helpers'
import type { TransactionRowIdentity } from '../activity/transaction-row'

/** The scope a recurring edit/delete applies to. */
export type RecurrenceScope = 'only-this' | 'all-future'

/** An account or category as the list hands it over: colour already
 * normalized to a concrete value, so a row never has to fall back. */
type NamedEntity = { id: string; name: string; icon?: string; color: string }

/**
 * The account and category chips under a row, resolved from the user's real
 * entities — the same two identities the Activity list shows, so an upcoming
 * movement is visually indistinguishable from one that already happened.
 */
export function identitiesFor(
    txn: ActivityTransaction,
    messages: Messages,
    accountsById: ReadonlyMap<string, NamedEntity>,
    categoriesById: ReadonlyMap<string, NamedEntity>,
): TransactionRowIdentity[] {
    const account = accountsById.get(txn.accountId)
    const category = categoriesById.get(txn.categoryId)
    return [
        ...(account
            ? [
                  {
                      type: 'account' as const,
                      label: messages.futureMovements.accountIdentity(
                          account.name,
                      ),
                      icon: account.icon,
                      color: account.color,
                  },
              ]
            : []),
        ...(category
            ? [
                  {
                      type: 'category' as const,
                      label: messages.futureMovements.categoryIdentity(
                          category.name,
                      ),
                      icon: category.icon,
                      color: category.color,
                  },
              ]
            : []),
    ]
}

export type FutureEntry =
    | { kind: 'header'; key: string; label: string }
    | {
          kind: 'txn'
          key: string
          txn: ActivityTransaction
          amountCents: number
      }

/**
 * Groups upcoming movements into day sections, sorted **ascending** (soonest
 * first) — the opposite of the Activity history, which shows newest first.
 * These have not happened yet, so the nearest one belongs at the top.
 */
export function buildFutureEntries(
    items: readonly ActivityTransaction[],
    nowMs: number,
    messages: Messages,
    locale: string,
): FutureEntry[] {
    const sorted = [...items].sort((left, right) => {
        const byDate = Number(left.date - right.date)
        if (byDate !== 0) return byDate
        const byCreation = Number(left.createdAt - right.createdAt)
        if (byCreation !== 0) return byCreation
        return left.id.localeCompare(right.id)
    })

    const entries: FutureEntry[] = []
    let currentDay: number | null = null
    for (const txn of sorted) {
        const dt = new Date(Number(txn.date))
        const day = new Date(
            dt.getFullYear(),
            dt.getMonth(),
            dt.getDate(),
        ).getTime()
        if (currentDay === null || day !== currentDay) {
            entries.push({
                kind: 'header',
                key: `header-${day}`,
                label: sectionLabel(day, nowMs, messages, locale),
            })
            currentDay = day
        }
        entries.push({
            kind: 'txn',
            key: txn.id,
            txn,
            amountCents: signedAmountCents(txn),
        })
    }
    return entries
}
