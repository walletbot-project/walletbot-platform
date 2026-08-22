import { Fab } from 'actify'
import { Outlet, useLocation, useNavigate } from 'react-router-dom'
import { AgentGlyph } from '@/components/m3/agent-glyph'
import {
    NavigationBar,
    type NavigationDestination,
    NavigationRail,
} from '@/components/m3/navigation'
import { useWindowSizeClass } from '@/hooks/use-window-size-class'
import type { Messages } from '@/lib/i18n'
import { useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'

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
        icon: 'bookmarks',
        end: false,
    },
] as const

function pathMatches(path: string, to: string, end: boolean) {
    return end ? path === to : path === to || path.startsWith(`${to}/`)
}

/**
 * The app shell, mirroring the native `Scaffold` in `apps/native/lib/main.dart`:
 * a bottom navigation bar with a centre-docked voice FAB on compact windows,
 * and a navigation rail carrying the FAB in the middle of its destinations from
 * medium windows up.
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

    /* The glyph mirrors native's `_VoiceFabIcon` (apps/native/lib/main.dart). */
    const voiceFab = (
        <span title={t.nav.addWithGasti}>
            <Fab
                aria-label={t.nav.addWithGasti}
                onPress={() => navigate('/add')}
                className="m3-fab"
            >
                <AgentGlyph />
            </Fab>
        </span>
    )

    /*
     * ONE tree for both shells. The rail and the bottom bar are conditional
     * siblings, but `<main>` — which holds the entire routed page — is emitted
     * unconditionally and always at the same child index, so crossing 600px
     * only rewrites classNames.
     *
     * This is load-bearing, not tidiness. Returning two different trees (which
     * this file used to do) put `<Outlet />` at index 2 in one and index 0 in
     * the other, so React unmounted and rebuilt the whole page every time the
     * window crossed 600px. Every `useState` in the active page reset — which
     * is what made an open Add Account / Add Tag / Add Category screen vanish
     * on resize. Never reintroduce a second `return` here.
     */
    return (
        <div
            className={cn(
                'flex h-dvh w-full overflow-hidden bg-surface',
                useRail ? 'flex-row' : 'flex-col',
            )}
        >
            {useRail ? (
                <NavigationRail
                    destinations={destinations}
                    agentButton={voiceFab}
                />
            ) : null}
            {useRail ? (
                <div
                    aria-hidden
                    className="w-px shrink-0 self-stretch bg-outline-variant"
                />
            ) : null}
            <main className="flex min-h-0 flex-1 flex-col overflow-hidden">
                <Outlet />
            </main>
            {useRail ? null : (
                <div className="relative">
                    {/*
                     * Centre-docked FAB, matching
                     * `FloatingActionButtonLocation.centerDocked`: it straddles
                     * the top edge of the navigation bar.
                     */}
                    <div className="pointer-events-none absolute inset-x-0 -top-7 z-10 flex justify-center">
                        <div className="pointer-events-auto">{voiceFab}</div>
                    </div>
                    <NavigationBar destinations={destinations} />
                </div>
            )}
        </div>
    )
}
