import { useContext } from 'react'
import { ThemeContext, type ThemeContextValue } from './context'

export {
    type Brightness,
    readSystemBrightness,
    readThemePreference,
    resolveBrightness,
    type ThemePreference,
    watchSystemBrightness,
    writeThemePreference,
} from './preference'

/** Theme preference + resolved brightness. Throws outside `ThemeProvider`. */
export function useTheme(): ThemeContextValue {
    const ctx = useContext(ThemeContext)
    if (!ctx) {
        throw new Error('useTheme must be used within a ThemeProvider')
    }
    return ctx
}
