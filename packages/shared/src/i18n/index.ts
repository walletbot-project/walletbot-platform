import { en, type TranslationKey } from './keys'

/**
 * Current locale dictionary. When we add multi-language support,
 * this will be swapped based on user preference.
 */
let currentDictionary: Record<TranslationKey, string> = { ...en }

/**
 * Look up a translated string by key.
 * Returns the key itself if no translation is found (makes missing keys visible in UI).
 */
export function t(key: TranslationKey): string {
    return currentDictionary[key] ?? key
}

/**
 * Set the active dictionary. Used when we add locale switching.
 */
export function setDictionary(
    dictionary: Record<TranslationKey, string>,
): void {
    currentDictionary = dictionary
}

export { en, type TranslationKey } from './keys'
