import type { RoleKey } from '@wallet-bot/shared/roles'
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

/**
 * Current user's role keys.
 */
export function useUserRoles(): string[] {
    return useAuth().roles
}

/**
 * Check if the current user has a specific role (client-side, no server call).
 */
export function useHasRole(role: RoleKey): boolean {
    return useAuth().hasRole(role)
}
