import { api } from '@wallet-bot/backend/api'
import { useQuery } from 'convex/react'
import { Outlet } from 'react-router-dom'
import { StateMessage } from '@/components/m3/state-message'
import { Skeleton } from '@/components/ui/skeleton'
import { useT } from '@/lib/i18n'

/**
 * Renders the backoffice routes only for admins. This is presentation, not
 * security: every admin query and mutation still runs `requireAdmin` on the
 * server.
 */
export function AdminGuard() {
    const t = useT()
    const isAdmin = useQuery(api.v1.featureFlags.queries.getMyAdminStatus)

    if (isAdmin === undefined) {
        return (
            <div className="flex flex-1 flex-col gap-4 p-4">
                <Skeleton className="h-24 w-full" />
                <Skeleton className="h-24 w-full" />
            </div>
        )
    }

    if (!isAdmin) {
        return (
            <StateMessage
                icon="lock"
                title={t.admin.notAdminTitle}
                detail={t.admin.notAdmin}
            />
        )
    }

    return <Outlet />
}
