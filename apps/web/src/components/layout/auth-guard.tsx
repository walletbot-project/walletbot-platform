import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { AuthProvider } from '@/components/layout/auth-provider'
import { VoiceProvider } from '@/components/layout/voice-provider'
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
            {/*
             * Above the router, so the assistant conversation survives every
             * navigation, and inside AuthProvider, so it ends with the account.
             */}
            <VoiceProvider>
                <Outlet />
            </VoiceProvider>
        </AuthProvider>
    )
}
