import { VALID_CATEGORIES } from './constants'

export function validateCategory(category: string): string {
    const normalized = category.toLowerCase().trim()
    if (
        !VALID_CATEGORIES.includes(
            normalized as (typeof VALID_CATEGORIES)[number],
        )
    ) {
        throw new Error(
            `Invalid category "${category}". Valid: ${VALID_CATEGORIES.join(', ')}`,
        )
    }
    return normalized
}

export function todayDateString(): string {
    return new Date().toISOString().slice(0, 10)
}
