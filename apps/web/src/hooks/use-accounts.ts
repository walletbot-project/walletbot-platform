import { api } from '@wallet-bot/backend/api'
import { useQuery } from 'convex/react'

export function useAccounts() {
    const accounts = useQuery(api.accounts.queries.listAccounts)
    return {
        accounts: accounts ?? [],
        defaultAccount: accounts?.find((a) => a.isDefault),
        isLoading: accounts === undefined,
    }
}
