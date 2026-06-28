import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useCachedSession } from '@/hooks/use-cached-session'

export function PublicGuard() {
    const { session, isInitialLoading } = useCachedSession()
    const location = useLocation()
    const from = location.state?.from?.pathname || '/'

    if (isInitialLoading) return null

    if (session) {
        return <Navigate to={from} replace />
    }

    return <Outlet />
}
