import { authClient } from '@/lib/auth-client'

type SessionData = ReturnType<typeof authClient.useSession>['data']

// Module-level cache shared across every guard so the last resolved session
// survives component remounts as well as background refetches.
let cachedSession: SessionData = null
let hasSettled = false

/**
 * Wraps Better Auth's `useSession` so the UI never flickers while the session
 * is re-fetched in the background.
 *
 * Better Auth flips `isPending` back to `true` on every background refetch
 * (e.g. on navigation or window focus). Guards that key off `isPending`
 * therefore blank the screen — and momentarily redirect to `/login` — on each
 * refetch. This hook returns the last resolved session during those refetches
 * and only reports loading before the very first resolution.
 */
export function useCachedSession(): {
    session: SessionData
    isInitialLoading: boolean
} {
    const { data, isPending } = authClient.useSession()

    if (!isPending) {
        cachedSession = data
        hasSettled = true
    }

    return {
        session: hasSettled ? cachedSession : data,
        isInitialLoading: isPending && !hasSettled,
    }
}
