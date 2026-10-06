import { api } from '@wallet-bot/backend/api'
import {
    nextPromptSuggestions,
    PROMPT_SUGGESTION_MOVEMENTS_CAP,
    type PromptSuggestion,
    pastCutoffBigInt,
} from '@wallet-bot/shared'
import { useConvex } from 'convex/react'
import { useEffect, useState } from 'react'

/**
 * One draw of prompt suggestions per mount of the agent page: a new set on
 * every open, read once rather than subscribed so the chips never reshuffle
 * under the user's finger. Mirrors native `loadSuggestionData`.
 */
export function usePromptSuggestions(enabled: boolean): PromptSuggestion[] {
    const convex = useConvex()
    const [suggestions, setSuggestions] = useState<PromptSuggestion[]>([])

    useEffect(() => {
        if (!enabled) return
        let cancelled = false
        void Promise.all([
            convex.query(api.v1.accounts.queries.listActive),
            convex.query(api.v1.categories.queries.listActive),
            convex.query(api.v1.tags.queries.listActiveWithCounts, {}),
            convex.query(api.v1.transactions.queries.recent, {
                limit: PROMPT_SUGGESTION_MOVEMENTS_CAP,
                asOfMs: pastCutoffBigInt(),
            }),
        ])
            .then(([accounts, categories, tags, movements]) => {
                if (cancelled) return
                setSuggestions(
                    nextPromptSuggestions({
                        accounts: accounts.map((a) => ({
                            id: a.id,
                            name: a.name,
                            currency: a.currency,
                        })),
                        categories: categories.map((c) => ({
                            id: c.id,
                            name: c.name,
                        })),
                        tags: tags.map((t) => ({
                            name: t.name,
                            usageCount: t.transactionCount,
                        })),
                        movements: movements.map((m) => ({
                            type: m.type,
                            amountCents: Number(m.amount),
                            currency: m.currency,
                            accountId: m.accountId,
                            categoryId: m.categoryId,
                            toAccountId: m.toAccountId,
                        })),
                    }),
                )
            })
            .catch((error: unknown) => {
                console.error('[voice] prompt suggestions failed', error)
            })
        return () => {
            cancelled = true
        }
    }, [convex, enabled])

    return suggestions
}
