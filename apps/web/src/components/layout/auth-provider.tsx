import { api } from '@wallet-bot/backend/api'
import type { RoleKey } from '@wallet-bot/shared/roles'
import { roles, rolesGranting } from '@wallet-bot/shared/roles'
import { useQuery } from 'convex/react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { authClient } from '@/lib/auth-client'
import { AuthContext, type AuthUser } from '@/lib/auth-context'

// -- localStorage cache --

const USER_CACHE_KEY = 'auth:user'
const ROLES_CACHE_KEY = 'auth:roles'

function getCachedUser(): AuthUser | null {
    try {
        const raw = localStorage.getItem(USER_CACHE_KEY)
        return raw ? JSON.parse(raw) : null
    } catch {
        return null
    }
}

function getCachedRoles(): string[] {
    try {
        const raw = localStorage.getItem(ROLES_CACHE_KEY)
        return raw ? JSON.parse(raw) : []
    } catch {
        return []
    }
}

function setCachedUser(user: AuthUser) {
    localStorage.setItem(USER_CACHE_KEY, JSON.stringify(user))
}

function setCachedRoles(userRoles: string[]) {
    localStorage.setItem(ROLES_CACHE_KEY, JSON.stringify(userRoles))
}

function clearCache() {
    localStorage.removeItem(USER_CACHE_KEY)
    localStorage.removeItem(ROLES_CACHE_KEY)
}

// -- Provider --

export function AuthProvider({ children }: { children: React.ReactNode }) {
    const navigate = useNavigate()

    // Cached state for instant render
    const [cachedUser] = useState(getCachedUser)
    const [cachedRoles] = useState(getCachedRoles)

    // Fresh data from Convex
    const convexUser = useQuery(api.auth.queries.getCurrentUser)
    const convexRoles = useQuery(api.auth.queries.getCurrentUserRoles)

    // Determine current user — prefer fresh data, fall back to cache
    const freshUser = useMemo<AuthUser | null>(
        () =>
            convexUser
                ? {
                      userId: convexUser._id,
                      name: convexUser.name ?? '',
                      email: convexUser.email,
                      image: convexUser.image ?? undefined,
                  }
                : null,
        [convexUser],
    )

    const user = freshUser ?? cachedUser
    const userRoles = convexRoles !== undefined ? convexRoles : cachedRoles
    const isLoading = convexUser === undefined || convexRoles === undefined

    // Update cache when fresh data arrives
    useEffect(() => {
        if (freshUser) setCachedUser(freshUser)
    }, [freshUser])

    useEffect(() => {
        if (convexRoles !== undefined) setCachedRoles(convexRoles)
    }, [convexRoles])

    const hasRole = useCallback(
        (role: RoleKey): boolean => {
            const grantors = rolesGranting(role, roles)
            return userRoles.some((r) => grantors.has(r))
        },
        [userRoles],
    )

    const signOut = useCallback(async () => {
        clearCache()
        await authClient.signOut()
        navigate('/login')
    }, [navigate])

    const value = useMemo(() => {
        if (!user) return null
        return { user, roles: userRoles, hasRole, signOut, isLoading }
    }, [user, userRoles, hasRole, signOut, isLoading])

    // No user at all (no cache, no fresh data yet) — wait
    if (!value) return null

    return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
