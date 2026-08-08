import type { Messages } from '@/lib/i18n'

// Matches the message thrown by convex/v1/accounts/mutations.ts when a
// name+currency combo collides with another active account.
const DUPLICATE_NAME_CURRENCY_MARKER = 'name and currency already exists'

export function accountErrorMessage(
    error: unknown,
    t: Messages,
    fallback: string,
): string {
    if (
        error instanceof Error &&
        error.message.includes(DUPLICATE_NAME_CURRENCY_MARKER)
    ) {
        return t.accounts.duplicateNameCurrency
    }
    return fallback
}
