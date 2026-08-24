import { useConvex } from 'convex/react'
import { useCallback, useContext, useMemo } from 'react'
import { useVoice } from '@/hooks/use-voice'
import { buildLiveTokenMintArgs } from '@/lib/agent-context'
import { AuthContext } from '@/lib/auth-context'
import { useI18n } from '@/lib/i18n'
import { ThemeContext } from '@/lib/theme/context'
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
 *
 * It also assembles the mint request for `requestLiveToken`: the auth and
 * i18n contexts all sit above this provider, so this is where the user's
 * identity, locale and data snapshot come together.
 */
export function VoiceProvider({ children }: { children: React.ReactNode }) {
    const client = useConvex()
    const auth = useContext(AuthContext)
    const { formatLocale, setPreference: setLanguage } = useI18n()
    const theme = useContext(ThemeContext)
    const setTheme = theme?.setPreference

    const user = auth?.user ?? null
    const buildMintArgs = useCallback(
        () =>
            buildLiveTokenMintArgs({
                client,
                user: user ? { name: user.name, email: user.email } : null,
                locale: formatLocale,
            }),
        [client, user, formatLocale],
    )

    // The `updateSettings` tool writes device settings through the providers
    // that own them (i18n + theme both sit above this provider).
    const settings = useMemo(
        () =>
            setTheme
                ? {
                      setLanguage,
                      setTheme,
                  }
                : undefined,
        [setLanguage, setTheme],
    )

    const voice = useVoice({ context: { client, settings }, buildMintArgs })

    return (
        <VoiceSessionContext.Provider value={voice}>
            {children}
        </VoiceSessionContext.Provider>
    )
}
