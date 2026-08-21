import { createContext } from 'react'
import type { Brightness, ThemePreference } from './preference'

export type ThemeContextValue = {
    /** What the user picked in the theme setting. */
    preference: ThemePreference
    setPreference: (preference: ThemePreference) => void
    /** The brightness actually painted, once `system` has been resolved. */
    brightness: Brightness
}

export const ThemeContext = createContext<ThemeContextValue | null>(null)
