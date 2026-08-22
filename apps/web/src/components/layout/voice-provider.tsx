import { useConvex } from 'convex/react'
import { useVoice } from '@/hooks/use-voice'
import { VoiceSessionContext } from '@/lib/voice-context'

/**
 * Owns the Live session for the signed-in account.
 *
 * It is mounted above `RootLayout`, inside `AuthProvider`, and deliberately not
 * inside the `/add` page: a route unmounts on every navigation, and it used to
 * take the socket, the running agent and the whole transcript with it, so
 * stepping over to Accounts and back landed on an empty screen.
 *
 * Native has exactly this ownership. `GeminiVoiceExpenseCommand` lives in
 * `GeminiVoiceExpenseCommandFactory`, provided above the navigator
 * (`apps/native/lib/main.dart`), so popping `VoiceScreen` leaves the
 * conversation running and reopening it re-attaches
 * (`apps/native/lib/screens/voice.dart`).
 *
 * Sitting inside `AuthProvider` is what ends the session when the account goes
 * away — the provider unmounts, `useVoice` disconnects. That is native's
 * `PopOnAccountSwitch`.
 */
export function VoiceProvider({ children }: { children: React.ReactNode }) {
    const client = useConvex()
    const voice = useVoice({ context: { client } })

    return (
        <VoiceSessionContext.Provider value={voice}>
            {children}
        </VoiceSessionContext.Provider>
    )
}
