import type { Messages } from './es'

/**
 * Localizes the auto-generated names the app (and the backend) persist for
 * balance-adjustment transactions. The stored value is a fixed cross-platform
 * constant — `packages/backend/convex/v1/transactions/mutations.ts` writes
 * `Ajuste de saldo` and `apps/web/src/pages/accounts/index.tsx` writes
 * `Balance inicial` — so it is mapped at render time rather than at write time.
 * That keeps the synced wire value stable and localizes rows that were already
 * persisted.
 *
 * `type` is the transaction's wire type. Only balance adjustments carry
 * generated names, so every other type passes through verbatim: an expense a
 * user literally named `Initial balance` keeps that name when the locale
 * changes.
 *
 * Both spellings are accepted because either client may have written the row —
 * an English native user's seed persists the English string.
 *
 * Display only: never feed this through an editable field, or saving would
 * persist the localized copy in place of the canonical name.
 *
 * Mirrors `transactionName` in `apps/native/lib/l10n/l10n.dart`.
 */
export function transactionName(
    value: string,
    type: string,
    t: Messages,
): string {
    if (type !== 'balance_adjustment') return value
    switch (value) {
        case 'Ajuste de saldo':
        case 'Balance adjustment':
            return t.transaction.balanceAdjustment
        case 'Balance inicial':
        case 'Initial balance':
            return t.transaction.initialBalance
        default:
            return value
    }
}

/**
 * The same mapping for the titles of the seeded default dashboard. Both clients
 * seed in the locale that was active at the time (`default-dashboard.ts`,
 * `apps/native/lib/components/dashboard/default_dashboard.dart`), so a title
 * written on one device reads correctly on another.
 *
 * Display only, for the same reason as `transactionName`: the widget sheet's
 * title field keeps the stored value.
 *
 * Mirrors `dashboardTitle` in `apps/native/lib/l10n/l10n.dart`.
 */
export function dashboardTitle(value: string, t: Messages): string {
    switch (value) {
        case 'Gastos del mes':
        case 'Monthly expenses':
            return t.dashboard.defaultExpensesMonth
        case 'Ingresos del mes':
        case 'Monthly income':
            return t.dashboard.defaultIncomeMonth
        case 'Movimientos del mes':
        case 'Monthly transactions':
            return t.dashboard.defaultMovementsMonth
        // The seeded balance tile names its currency, and the seed always uses
        // `DEFAULT_CURRENCY`, so the code in the canonical string is part of the
        // match — it is not the reader's own currency.
        case 'Saldo total (ARS)':
        case 'Total balance (ARS)':
            return t.dashboard.defaultTotalBalance({ currency: 'ARS' })
        case 'Movimientos':
        case 'Transactions':
            return t.dashboard.defaultMovements
        case 'Movimientos recientes':
        case 'Recent transactions':
            return t.dashboard.defaultRecentMovements
        default:
            return value
    }
}
