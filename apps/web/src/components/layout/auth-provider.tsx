import { useCallback, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { authClient } from '@/lib/auth-client'
import { AuthContext } from '@/lib/auth-context'

export function AuthProvider({ children }: { children: React.ReactNode }) {
    const navigate = useNavigate()
    const { data: session } = authClient.useSession()

    const signOut = useCallback(async () => {
        await authClient.signOut()
        navigate('/login')
    }, [navigate])

    const value = useMemo(() => {
        if (!session?.user) return null
        return {
            user: {
                userId: session.user.id,
                name: session.user.name ?? '',
                email: session.user.email,
                image: session.user.image ?? undefined,
            },
            signOut,
        }
    }, [session, signOut])

    if (!value) return null

    return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
