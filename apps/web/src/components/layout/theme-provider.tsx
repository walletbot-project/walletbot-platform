import { useCallback, useEffect, useMemo, useState } from 'react'
import {
    readSystemBrightness,
    readThemePreference,
    resolveBrightness,
    type ThemePreference,
    watchSystemBrightness,
    writeThemePreference,
} from '@/lib/theme'
import { ThemeContext } from '@/lib/theme/context'

/**
 * Applies the user's light/dark choice, mirroring the native app's
 * `DisplaySettingsController` — same tri-state, same storage key, and the same
 * behaviour of following the OS while the app is open under `system`.
 */
export function ThemeProvider({ children }: { children: React.ReactNode }) {
    const [preference, setPreferenceState] =
        useState<ThemePreference>(readThemePreference)
    const [systemBrightness, setSystemBrightness] =
        useState(readSystemBrightness)

    useEffect(
        () =>
            watchSystemBrightness(() =>
                setSystemBrightness(readSystemBrightness()),
            ),
        [],
    )

    const setPreference = useCallback((next: ThemePreference) => {
        writeThemePreference(next)
        setPreferenceState(next)
    }, [])

    const value = useMemo(() => {
        return {
            preference,
            setPreference,
            brightness: resolveBrightness(preference, systemBrightness),
        }
    }, [preference, systemBrightness, setPreference])

    useEffect(() => {
        document.documentElement.classList.toggle(
            'dark',
            value.brightness === 'dark',
        )
    }, [value.brightness])

    return (
        <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>
    )
}
