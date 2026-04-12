import { api } from '@wallet-bot/backend/api'
import { useQuery } from 'convex/react'

const DEFAULTS = { defaultCurrency: 'USD', locale: 'en-US' } as const

export function useUserSettings() {
    const settings = useQuery(api.settings.queries.getUserSettings)
    return {
        settings: settings ?? DEFAULTS,
        isLoading: settings === undefined,
    }
}
