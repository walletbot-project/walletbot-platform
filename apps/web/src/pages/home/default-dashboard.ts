import {
    DEFAULT_CURRENCY,
    EMPTY_FILTER,
    filterConfigToJson,
} from '@wallet-bot/shared'
import type { Messages } from '@/lib/i18n'

/**
 * The default v1 dashboard, mirroring the native seed
 * (apps/native/lib/components/dashboard/default_dashboard.dart) — same
 * **deterministic ids**, so a device and the web app seeding the same fresh
 * account converge under last-writer-wins instead of duplicating the layout.
 */
const EXPENSE_FILTER_ID = 'seed-flt-gastos-mes'
const INCOME_FILTER_ID = 'seed-flt-ingresos-mes'
const MONTH_FILTER_ID = 'seed-flt-movimientos-mes'

export type SeedPayload = {
    filters: { id: string; name: string; config: string }[]
    widgets: {
        id: string
        type: string
        filterId?: string
        position: number
        width: string
        options: string
    }[]
}

export function defaultDashboardSeed(t: Messages): SeedPayload {
    // The monetary tiles are scoped to the app's default currency, matching the
    // native seed; sums for users without transactions in it read as 0.
    const currency = DEFAULT_CURRENCY

    const options = (
        content: Record<string, unknown>,
        row: number,
        col: number,
    ) => JSON.stringify({ ...content, layout: { row, col } })

    return {
        filters: [
            {
                id: EXPENSE_FILTER_ID,
                name: t.dashboard.defaultExpensesMonth,
                config: filterConfigToJson({
                    ...EMPTY_FILTER,
                    types: ['expense'],
                    datePreset: 'this_month',
                    currency,
                }),
            },
            {
                id: INCOME_FILTER_ID,
                name: t.dashboard.defaultIncomeMonth,
                config: filterConfigToJson({
                    ...EMPTY_FILTER,
                    types: ['income'],
                    datePreset: 'this_month',
                    currency,
                }),
            },
            {
                id: MONTH_FILTER_ID,
                name: t.dashboard.defaultMovementsMonth,
                config: filterConfigToJson({
                    ...EMPTY_FILTER,
                    datePreset: 'this_month',
                }),
            },
        ],
        widgets: [
            {
                id: 'seed-wgt-saldo',
                type: 'balance',
                position: 0,
                width: 'full',
                options: options(
                    {
                        title: t.dashboard.defaultTotalBalance({ currency }),
                        currency,
                    },
                    0,
                    0,
                ),
            },
            {
                id: 'seed-wgt-gastos',
                type: 'stat',
                filterId: EXPENSE_FILTER_ID,
                position: 1,
                width: 'third',
                options: options(
                    {
                        title: t.dashboard.defaultExpensesMonth,
                        aggregation: 'sum',
                    },
                    1,
                    0,
                ),
            },
            {
                id: 'seed-wgt-ingresos',
                type: 'stat',
                filterId: INCOME_FILTER_ID,
                position: 2,
                width: 'third',
                options: options(
                    {
                        title: t.dashboard.defaultIncomeMonth,
                        aggregation: 'sum',
                    },
                    1,
                    2,
                ),
            },
            {
                id: 'seed-wgt-movimientos',
                type: 'stat',
                filterId: MONTH_FILTER_ID,
                position: 3,
                width: 'third',
                options: options(
                    {
                        title: t.dashboard.defaultMovements,
                        aggregation: 'count',
                    },
                    1,
                    4,
                ),
            },
            {
                id: 'seed-wgt-recientes',
                type: 'list',
                position: 4,
                width: 'full',
                options: options(
                    { title: t.dashboard.defaultRecentMovements, limit: 5 },
                    2,
                    0,
                ),
            },
        ],
    }
}
