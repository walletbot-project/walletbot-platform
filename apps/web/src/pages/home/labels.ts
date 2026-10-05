import type { DashboardWidth, WidgetType } from '@wallet-bot/shared'
import { dashboardTitle, type Messages } from '@/lib/i18n'

/** The catalog label for a tile width — shared by the dashboard's width chips
 * and the widget sheet's width selector. */
export function widthLabel(width: DashboardWidth, t: Messages): string {
    switch (width) {
        case 'third':
            return t.dashboard.widthThird
        case 'half':
            return t.dashboard.widthHalf
        case 'two_thirds':
            return t.dashboard.widthTwoThirds
        case 'full':
            return t.dashboard.widthFull
    }
}

/**
 * The catalog label for a widget type — the sheet's type chips, and the name a
 * widget falls back to when it has no title (native `dashboardFallbackType`).
 */
export function widgetTypeLabel(type: WidgetType, t: Messages): string {
    switch (type) {
        case 'stat':
            return t.dashboard.typeStat
        case 'list':
            return t.dashboard.typeList
        case 'balance':
            return t.dashboard.typeBalance
        case 'chart':
            return t.dashboard.typeChart
        case 'balance_comparison':
            return t.dashboard.typeBalanceComparison
    }
}

/**
 * The display name of a stored widget row: its title when it has one, its type
 * otherwise — `_titleOf` in `dashboard_section.dart`. `type` is the raw stored
 * string, so a row written by a newer client still names itself.
 */
export function widgetLabel(title: string, type: string, t: Messages): string {
    if (title) return dashboardTitle(title, t)
    switch (type) {
        case 'stat':
        case 'list':
        case 'balance':
        case 'chart':
        case 'balance_comparison':
            return widgetTypeLabel(type, t)
        default:
            return t.dashboard.widget
    }
}
