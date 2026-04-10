import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { AuthProvider } from '@/components/layout/auth-provider'
import { authClient } from '@/lib/auth-client'

export function AuthGuard() {
    const { data: session, isPending } = authClient.useSession()
    const location = useLocation()

    if (isPending) return null

    if (!session) {
        return <Navigate to="/login" state={{ from: location }} replace />
    }

    return (
        <AuthProvider>
            <Outlet />
        </AuthProvider>
    )
}
