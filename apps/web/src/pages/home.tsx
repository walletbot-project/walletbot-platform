import { api } from '@wallet-bot/backend/api'
import { type LayoutCoord, parseWidgetOptions } from '@wallet-bot/shared'
import { IconButton } from 'actify'
import { useQuery } from 'convex/react'
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { AppBar } from '@/components/m3/app-bar'
import { BottomSheet } from '@/components/m3/bottom-sheet'
import { GroupedCard } from '@/components/m3/grouped-card'
import { Icon } from '@/components/m3/icon'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import { useAuth, useUser } from '@/hooks/use-auth'
import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import { useT } from '@/lib/i18n'
import { Dashboard, type DashboardWidgetRow } from '@/pages/home/dashboard'
import { FeedbackSheet } from '@/pages/home/feedback-sheet'
import { WidgetSheet } from '@/pages/home/widget-sheet'

export default function Home() {
    const t = useT()
    const navigate = useNavigate()
    const [menuOpen, setMenuOpen] = useState(false)
    const [editing, setEditing] = useState(false)
    const [feedbackOpen, setFeedbackOpen] = useState(false)
    // `null` while closed; `{ widget: null }` is the add flow, and `at` marks
    // the grid cell a `+` placeholder targeted (null = a fresh bottom row).
    const [sheet, setSheet] = useState<{
        widget: DashboardWidgetRow | null
        at: LayoutCoord | null
        maxUnits: number | null
        key: number
    } | null>(null)

    const layout = useQuery(api.v1.dashboard.queries.layout)
    const flags = useQuery(api.v1.featureFlags.queries.getMyFlags)
    // A new tile lands on its own row past everything already placed.
    const nextRow = (layout?.widgets ?? []).reduce((max, widget) => {
        const coord = parseWidgetOptions(widget.options).layout
        return coord ? Math.max(max, coord.row + 1) : max
    }, 0)
    const nextPosition = layout?.widgets.length ?? 0

    const openSheet = (
        widget: DashboardWidgetRow | null,
        at: LayoutCoord | null = null,
        maxUnits: number | null = null,
    ) => setSheet({ widget, at, maxUnits, key: Date.now() })

    return (
        <>
            <AppBar
                title={t.nav.home}
                actions={
                    editing ? (
                        <>
                            <IconButton
                                aria-label={t.dashboard.addWidget}
                                onPress={() => openSheet(null)}
                                className="text-on-surface-variant"
                            >
                                <Icon name="add" />
                            </IconButton>
                            <IconButton
                                aria-label={t.common.done}
                                onPress={() => setEditing(false)}
                                className="text-on-surface-variant"
                            >
                                <Icon name="check" />
                            </IconButton>
                        </>
                    ) : (
                        <>
                            <IconButton
                                aria-label={t.dashboard.editDashboard}
                                onPress={() => setEditing(true)}
                                className="text-on-surface-variant"
                            >
                                <Icon name="edit" />
                            </IconButton>
                            <IconButton
                                aria-label={t.settings.account}
                                onPress={() => setMenuOpen(true)}
                                className="text-on-surface-variant"
                            >
                                <Icon name="person" filled />
                            </IconButton>
                        </>
                    )
                }
            />
            <div className="min-h-0 flex-1 overflow-y-auto">
                <div className="flex flex-col p-4 pb-24">
                    <Dashboard
                        editing={editing}
                        onStartEditing={() => setEditing(true)}
                        onEditWidget={(widget) => openSheet(widget)}
                        onAddWidgetAt={(at, maxUnits) =>
                            openSheet(null, at, maxUnits)
                        }
                    />

                    <h2 className="m3-title-medium mt-6">{t.nav.actions}</h2>
                    <div className="mt-3 flex flex-wrap gap-3">
                        <HomeActionCard
                            label={t.nav.addManually}
                            icon="add"
                            // The native home pushes the transaction form and
                            // lands on Activity once it saves; on web the form
                            // is a route under Activity, so we link straight
                            // at it.
                            onClick={() => navigate('/activity/new')}
                        />
                        {flags?.feedback ? (
                            <HomeActionCard
                                label={t.nav.sendFeedback}
                                icon="feedback"
                                onClick={() => setFeedbackOpen(true)}
                            />
                        ) : null}
                        <HomeActionCard
                            label={t.nav.futureMovements}
                            icon="event_repeat"
                            onClick={() => navigate('/future-movements')}
                        />
                    </div>
                </div>
            </div>

            {sheet ? (
                <WidgetSheet
                    key={sheet.key}
                    onOpenChange={(open) => {
                        if (!open) setSheet(null)
                    }}
                    widget={sheet.widget}
                    at={sheet.at}
                    maxUnits={sheet.maxUnits}
                    nextRow={nextRow}
                    nextPosition={nextPosition}
                />
            ) : null}

            <FeedbackSheet open={feedbackOpen} onOpenChange={setFeedbackOpen} />

            <AccountMenu open={menuOpen} onOpenChange={setMenuOpen} />
        </>
    )
}

/**
 * The square shortcut tile on the home screen, matching the native
 * `_HomeActionCard`: a 112dp outlined container with a filled accent circle
 * over a short two-line label.
 */
function HomeActionCard({
    label,
    icon,
    onClick,
}: {
    label: string
    icon: string
    onClick: () => void
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            className="m3-state-layer flex size-28 cursor-pointer flex-col items-center justify-center gap-2 rounded-[14px] border-[1.4px] border-outline-variant bg-surface-container p-2.5 text-on-surface"
        >
            <span className="flex size-11 items-center justify-center rounded-full bg-primary-container text-on-primary-container">
                <Icon name={icon} filled size={30} />
            </span>
            <span className="line-clamp-2 text-center text-[13px] leading-none font-black">
                {label}
            </span>
        </button>
    )
}

/**
 * The account sheet behind the app bar's person action, mirroring the native
 * account switcher: the signed-in account, then settings and sign-out.
 */
function AccountMenu({
    open,
    onOpenChange,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
}) {
    const t = useT()
    const navigate = useNavigate()
    const auth = useAuth()
    const user = useUser()
    const isAdmin = useQuery(api.v1.featureFlags.queries.getMyAdminStatus)
    // Same subscription the home screen holds; Convex dedupes it.
    const flags = useQuery(api.v1.featureFlags.queries.getMyFlags)

    const initials = (user.name || user.email)
        .split(' ')
        .map((part) => part[0])
        .filter(Boolean)
        .slice(0, 2)
        .join('')
        .toUpperCase()

    const go = (path: string) => {
        onOpenChange(false)
        navigate(path)
    }

    const items = [
        {
            key: 'settings',
            icon: 'settings',
            label: t.settings.title,
            onClick: () => go('/settings'),
        },
        // Only for accounts in the WhatsApp rollout. The route itself stays
        // open either way, so a number linked before the flag was switched off
        // can still be disconnected.
        ...(flags?.whatsapp
            ? [
                  {
                      key: 'whatsapp',
                      icon: 'chat',
                      label: t.whatsapp.title,
                      onClick: () => go('/whatsapp'),
                  },
              ]
            : []),
        ...(isAdmin
            ? [
                  {
                      key: 'feature-flags',
                      icon: 'flag',
                      label: t.settings.featureFlags,
                      onClick: () => go('/admin/feature-flags'),
                  },
              ]
            : []),
        {
            key: 'sign-out',
            icon: 'logout',
            label: t.nav.signOut,
            onClick: () => {
                onOpenChange(false)
                void auth.signOut()
            },
        },
    ]

    return (
        <BottomSheet
            open={open}
            onOpenChange={onOpenChange}
            title={t.settings.account}
        >
            <div className="flex flex-col px-4 pb-6">
                <div className="flex items-center gap-4 px-2 pb-5">
                    <Avatar size="lg">
                        {user.image ? <AvatarImage src={user.image} /> : null}
                        <AvatarFallback className="bg-tertiary-container text-on-tertiary-container">
                            {initials || <Icon name="person" filled />}
                        </AvatarFallback>
                    </Avatar>
                    <div className="flex min-w-0 flex-col">
                        <span className="m3-title-medium truncate">
                            {user.name || t.settings.account}
                        </span>
                        <span className="m3-body-small truncate text-on-surface-variant">
                            {user.email}
                        </span>
                    </div>
                </div>
                <div className="flex flex-col" style={{ gap: GROUP_SPACING }}>
                    {items.map((item, index) => (
                        <GroupedCard
                            key={item.key}
                            radius={groupedRadius(index, items.length)}
                            onClick={item.onClick}
                        >
                            <div className="flex items-center gap-4 px-4 py-4">
                                <Icon
                                    name={item.icon}
                                    filled
                                    className="text-on-surface-variant"
                                />
                                <span className="m3-body-large flex-1">
                                    {item.label}
                                </span>
                            </div>
                        </GroupedCard>
                    ))}
                </div>
            </div>
        </BottomSheet>
    )
}
