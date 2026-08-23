import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useUser } from '@/hooks/use-auth'
import {
    isLegalPromptDismissed,
    legalDismissalKey,
    useLegalAcceptance,
} from '@/hooks/use-legal-acceptance'

/**
 * Sends a signed-in user to `/accept-terms` until they have accepted the
 * current Terms and Privacy Policy — the same shape as `AuthGuard` sending an
 * anonymous visitor to `/login`.
 *
 * `blocking` (nothing accepted at or above the floor) has no way out but
 * accepting or signing out. A `prompt` inside the grace period can be
 * dismissed with "Later", which is remembered for this browser session.
 *
 * Renders nothing while the status is unknown, like `AuthGuard` does for the
 * session: mounting the app and then bouncing would remount the whole page.
 */
export function LegalGuard() {
    const status = useLegalAcceptance()
    const { userId } = useUser()
    const location = useLocation()

    if (status === undefined) return null

    const dismissed = isLegalPromptDismissed(legalDismissalKey(userId, status))
    if (status.prompt && (status.blocking || !dismissed)) {
        return (
            <Navigate to="/accept-terms" state={{ from: location }} replace />
        )
    }

    return <Outlet />
}
