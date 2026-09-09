import { api } from '@wallet-bot/backend/api'
import { useQuery } from 'convex/react'
import { Outlet } from 'react-router-dom'
import { NotFound } from '@/pages/not-found'

/**
 * Hides the routes the `recurringExpense` flag covers from a user the rollout
 * has not reached, the same shape as `LegalGuard` and `AuthGuard`.
 *
 * Hiding the entry points is not enough: the home card is already conditional,
 * but a URL stays typeable, stays in history, and stays bookmarked from before
 * the flag was turned off — and the screen behind it manages series the user
 * has no other way to see.
 *
 * Renders `NotFound` rather than redirecting home. With the flag off the page
 * genuinely does not exist for this user, so saying so beats teleporting them
 * somewhere they did not ask for, and keeping the URL means a reload is enough
 * once the rollout arrives.
 *
 * Renders nothing while the flags are unknown, like the other guards do for
 * the session: bouncing a user who *does* have the flag, on every load, until
 * the query resolves would be worse than a blank moment.
 */
export function RecurringExpenseGuard() {
    const flags = useQuery(api.v1.featureFlags.queries.getMyFlags)

    if (flags === undefined) return null
    if (flags.recurringExpense !== true) return <NotFound />

    return <Outlet />
}
