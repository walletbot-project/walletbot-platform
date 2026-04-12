import { api } from '@wallet-bot/backend/api'
import { useQuery } from 'convex/react'
import { useMemo } from 'react'

export function useCategories() {
    const categories = useQuery(api.categories.queries.listCategories)

    const flatCategories = useMemo(() => {
        if (!categories) return []
        const flat: (typeof categories)[number]['children'] = []
        for (const cat of categories) {
            flat.push(cat)
            for (const child of cat.children) {
                flat.push(child)
            }
        }
        return flat
    }, [categories])

    return {
        categories: categories ?? [],
        flatCategories,
        isLoading: categories === undefined,
    }
}
