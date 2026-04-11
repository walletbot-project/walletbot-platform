import { useContext } from 'react'
import {
    AuthContext,
    type AuthContextValue,
    type AuthUser,
} from '@/lib/auth-context'

/**
 * Full auth context. Throws if used outside AuthProvider.
 */
export function useAuth(): AuthContextValue {
    const ctx = useContext(AuthContext)
    if (!ctx) {
        throw new Error(
            'useAuth must be used within an AuthProvider (inside AuthGuard)',
        )
    }
    return ctx
}

/**
 * Current authenticated user. Guaranteed non-null inside AuthGuard.
 */
export function useUser(): AuthUser {
    return useAuth().user
}
