import { api } from '@wallet-bot/backend/api'
import { useQuery } from 'convex/react'

export function useTags() {
    const tags = useQuery(api.tags.queries.listTags)
    return {
        tags: tags ?? [],
        isLoading: tags === undefined,
    }
}
