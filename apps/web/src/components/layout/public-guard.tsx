import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { authClient } from '@/lib/auth-client'

export function PublicGuard() {
    const { data: session, isPending } = authClient.useSession()
    const location = useLocation()
    const from = location.state?.from?.pathname || '/'

    if (isPending) return null

    if (session) {
        return <Navigate to={from} replace />
    }

    return <Outlet />
}
