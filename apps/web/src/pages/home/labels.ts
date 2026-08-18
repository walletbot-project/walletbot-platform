import type { DashboardWidth } from '@wallet-bot/shared'
import type { Messages } from '@/lib/i18n'

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
