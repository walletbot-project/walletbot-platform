import type { RoleKey } from '@wallet-bot/shared/roles'
import { createContext } from 'react'

export type AuthUser = {
    userId: string
    name: string
    email: string
    image?: string
}

export type AuthContextValue = {
    user: AuthUser
    roles: string[]
    hasRole: (role: RoleKey) => boolean
    signOut: () => Promise<void>
    isLoading: boolean
}

export const AuthContext = createContext<AuthContextValue | null>(null)
