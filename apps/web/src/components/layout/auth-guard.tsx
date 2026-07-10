import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { AuthProvider } from '@/components/layout/auth-provider'
import { useCachedSession } from '@/hooks/use-cached-session'

export function AuthGuard() {
    const { session, isInitialLoading } = useCachedSession()
    const location = useLocation()

    if (isInitialLoading) return null

    if (!session) {
        return <Navigate to="/login" state={{ from: location }} replace />
    }

    return (
        <AuthProvider>
            <Outlet />
        </AuthProvider>
    )
}
