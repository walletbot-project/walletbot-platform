/**
 * What the user picked in the theme setting. `system` follows the OS, mirroring
 * the native app's `DisplayTheme` tri-state
 * (apps/native/lib/settings/display_settings.dart).
 */
export type ThemePreference = 'system' | 'light' | 'dark'

/** The brightness actually painted, once `system` has been resolved. */
export type Brightness = 'light' | 'dark'

/**
 * Device-scoped, so it deliberately does not follow the account: the key name
 * matches the native app's SharedPreferences entry.
 */
const STORAGE_KEY = 'display_theme'

const DARK_QUERY = '(prefers-color-scheme: dark)'

export function readThemePreference(): ThemePreference {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (stored === 'light' || stored === 'dark' || stored === 'system') {
        return stored
    }
    return 'system'
}

export function writeThemePreference(preference: ThemePreference): void {
    if (preference === 'system') {
        localStorage.removeItem(STORAGE_KEY)
        return
    }
    localStorage.setItem(STORAGE_KEY, preference)
}

/** Whether the OS currently asks for a dark UI. */
export function readSystemBrightness(): Brightness {
    return window.matchMedia(DARK_QUERY).matches ? 'dark' : 'light'
}

/** Subscribes to OS-level light/dark changes; returns the unsubscribe. */
export function watchSystemBrightness(onChange: () => void): () => void {
    const query = window.matchMedia(DARK_QUERY)
    query.addEventListener('change', onChange)
    return () => query.removeEventListener('change', onChange)
}

export function resolveBrightness(
    preference: ThemePreference,
    system: Brightness,
): Brightness {
    return preference === 'system' ? system : preference
}
