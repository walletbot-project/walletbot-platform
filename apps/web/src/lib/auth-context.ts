import { createContext } from 'react'

export type AuthUser = {
    userId: string
    name: string
    email: string
    image?: string
}

export type AuthContextValue = {
    user: AuthUser
    signOut: () => Promise<void>
}

export const AuthContext = createContext<AuthContextValue | null>(null)
