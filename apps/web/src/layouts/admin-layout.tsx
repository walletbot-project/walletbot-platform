import { api } from '@wallet-bot/backend/api'
import { IconButton } from 'actify'
import { useQuery } from 'convex/react'
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { AppBar } from '@/components/m3/app-bar'
import { Icon } from '@/components/m3/icon'
import { Skeleton } from '@/components/ui/skeleton'
import type { Messages } from '@/lib/i18n'
import { useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'

const SECTIONS = [
    {
        to: '/admin/feature-flags',
        icon: 'flag',
        label: (t: Messages) => t.admin.navFlags,
    },
    {
        to: '/admin/feedback',
        icon: 'feedback',
        label: (t: Messages) => t.admin.navFeedback,
    },
    {
        to: '/admin/agent-reports',
        icon: 'report',
        label: (t: Messages) => t.admin.navReports,
    },
    {
        to: '/admin/metrics',
        icon: 'monitoring',
        label: (t: Messages) => t.admin.navMetrics,
    },
    {
        to: '/admin/users',
        icon: 'group',
        label: (t: Messages) => t.admin.navUsers,
    },
    {
        to: '/admin/transcripts',
        icon: 'forum',
        label: (t: Messages) => t.admin.navTranscripts,
    },
] as const

/**
 * The back office shell: one admin gate for every section, a section switcher
 * (a tab strip on narrow windows, a side list from `md` up) and the routed
 * section below.
 *
 * The gate here only decides what to render. It is not the access control:
 * every function a section calls re-checks the caller on the server, so a
 * non-admin who got past this screen would still read nothing.
 */
export function AdminLayout() {
    const t = useT()
    const navigate = useNavigate()
    const isAdmin = useQuery(api.v1.featureFlags.queries.getMyAdminStatus)

    if (isAdmin === undefined) {
        return (
            <div className="flex h-dvh flex-col gap-4 bg-surface p-4">
                <Skeleton className="h-16 w-full" />
                <Skeleton className="h-24 w-full" />
            </div>
        )
    }

    if (!isAdmin) {
        return (
            <div className="flex h-dvh flex-col items-center justify-center gap-2 bg-surface p-4 text-center">
                <h2 className="text-lg font-medium">{t.admin.title}</h2>
                <p className="text-sm text-muted-foreground">
                    {t.admin.notAdmin}
                </p>
            </div>
        )
    }

    return (
        <div className="flex h-dvh w-full flex-col overflow-hidden bg-surface text-on-surface">
            <AppBar
                title={t.admin.title}
                leading={
                    <IconButton
                        aria-label={t.admin.exit}
                        onPress={() => navigate('/')}
                        className="text-on-surface-variant"
                    >
                        <Icon name="arrow_back" />
                    </IconButton>
                }
            />
            <div className="flex min-h-0 flex-1 flex-col md:flex-row">
                <nav
                    aria-label={t.admin.sections}
                    className="flex shrink-0 gap-1 overflow-x-auto border-b border-outline-variant p-2 md:w-56 md:flex-col md:overflow-x-visible md:border-r md:border-b-0"
                >
                    {SECTIONS.map((section) => (
                        <NavLink
                            key={section.to}
                            to={section.to}
                            className={({ isActive }) =>
                                cn(
                                    'flex shrink-0 items-center gap-2 rounded-full px-4 py-2 text-sm whitespace-nowrap',
                                    isActive
                                        ? 'bg-secondary-container text-on-secondary-container'
                                        : 'text-on-surface-variant hover:bg-surface-container',
                                )
                            }
                        >
                            <Icon name={section.icon} size={20} />
                            {section.label(t)}
                        </NavLink>
                    ))}
                </nav>
                <main className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden">
                    <Outlet />
                </main>
            </div>
        </div>
    )
}
