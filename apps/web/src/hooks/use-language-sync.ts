import { api } from '@wallet-bot/backend/api'
import { useConvexAuth, useMutation } from 'convex/react'
import { useEffect, useRef } from 'react'
import type { LanguagePreference } from '@/lib/i18n'

/**
 * Reports the browser's language to the backend, which needs it to send email
 * (and later WhatsApp) in the right one. Nothing flows the other way: the
 * display language stays device-scoped, exactly as it was.
 *
 * `system` reports as `device` and never overwrites a language the user picked
 * by hand on any client; anything else reports as `explicit` and wins. The
 * server owns that rule (`resolveLanguageWrite`), and resolves the tag to a
 * shipped locale itself.
 *
 * Gated on Convex auth rather than the better-auth session: that is the state
 * that decides whether the mutation can authenticate at all.
 *
 * Failures are logged and forgotten. The push repeats on the next mount and on
 * every preference change, so a transient failure heals itself. Nothing here
 * is something the user asked for, so a toast for a background write they never
 * initiated would be noise.
 */
export function useLanguageSync(args: {
    preference: LanguagePreference
    formatLocale: string
}): void {
    const { preference, formatLocale } = args
    const { isAuthenticated } = useConvexAuth()
    const updateLanguage = useMutation(api.v1.users.mutations.updateLanguage)
    // What we last successfully pushed, so re-renders don't re-send it. Reset
    // on sign-out so the next account gets its own report.
    const pushed = useRef<string | null>(null)

    useEffect(() => {
        if (!isAuthenticated) {
            pushed.current = null
            return
        }
        const source = preference === 'system' ? 'device' : 'explicit'
        const key = `${source}:${formatLocale}`
        if (pushed.current === key) return

        let cancelled = false
        updateLanguage({ tag: formatLocale, source })
            .then(() => {
                if (!cancelled) pushed.current = key
            })
            .catch((error: unknown) => {
                console.warn('languageSync: push failed', error)
            })
        return () => {
            cancelled = true
        }
    }, [isAuthenticated, preference, formatLocale, updateLanguage])
}
