import { Fab } from 'actify'
import { Outlet, useLocation, useNavigate } from 'react-router-dom'
import {
    NavigationBar,
    type NavigationDestination,
    NavigationRail,
} from '@/components/m3/navigation'
import { useWindowSizeClass } from '@/hooks/use-window-size-class'
import type { Messages } from '@/lib/i18n'
import { useT } from '@/lib/i18n'

/**
 * The four primary destinations, in the same order as the native app's
 * bottom bar / rail (apps/native/lib/main.dart), using the same Material
 * icons.
 */
const NAV_ITEMS = [
    {
        to: '/',
        label: (t: Messages) => t.nav.home,
        icon: 'home',
        end: true,
    },
    {
        to: '/activity',
        label: (t: Messages) => t.nav.activity,
        icon: 'calendar_view_month',
        end: false,
    },
    {
        to: '/accounts',
        label: (t: Messages) => t.nav.accounts,
        icon: 'account_balance',
        end: false,
    },
    {
        to: '/insights',
        label: (t: Messages) => t.nav.insights,
        icon: 'stacked_line_chart',
        end: false,
    },
] as const

function pathMatches(path: string, to: string, end: boolean) {
    return end ? path === to : path === to || path.startsWith(`${to}/`)
}

/**
 * The app shell, mirroring the native `Scaffold` in `apps/native/lib/main.dart`:
 * a bottom navigation bar with a centre-docked voice FAB on compact windows,
 * and a navigation rail carrying the FAB in its leading slot from medium
 * windows up.
 */
export function RootLayout() {
    const location = useLocation()
    const navigate = useNavigate()
    const t = useT()
    const sizeClass = useWindowSizeClass()
    const useRail = sizeClass !== 'compact'

    const destinations: NavigationDestination[] = NAV_ITEMS.map((item) => ({
        to: item.to,
        icon: item.icon,
        label: item.label(t),
        isActive: pathMatches(location.pathname, item.to, item.end),
    }))

    const voiceFab = (
        <span title={t.nav.addWithGasti}>
            <Fab
                aria-label={t.nav.addWithGasti}
                onPress={() => navigate('/add')}
                className="bg-primary-container text-on-primary-container"
            >
                <span className="text-2xl leading-none">🤖</span>
            </Fab>
        </span>
    )

    const content = (
        <main className="flex min-h-0 flex-1 flex-col overflow-hidden">
            <Outlet />
        </main>
    )

    if (useRail) {
        return (
            <div className="flex h-dvh w-full overflow-hidden bg-surface">
                <NavigationRail
                    destinations={destinations}
                    leading={voiceFab}
                />
                <div
                    aria-hidden
                    className="w-px shrink-0 self-stretch bg-outline-variant"
                />
                {content}
            </div>
        )
    }

    return (
        <div className="flex h-dvh w-full flex-col overflow-hidden bg-surface">
            {content}
            <div className="relative">
                {/*
                 * Centre-docked FAB, matching
                 * `FloatingActionButtonLocation.centerDocked`: it straddles the
                 * top edge of the navigation bar.
                 */}
                <div className="pointer-events-none absolute inset-x-0 -top-7 z-10 flex justify-center">
                    <div className="pointer-events-auto">{voiceFab}</div>
                </div>
                <NavigationBar destinations={destinations} />
            </div>
        </div>
    )
}
