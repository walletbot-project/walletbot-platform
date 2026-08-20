import { api } from '@wallet-bot/backend/api'
import { useQuery } from 'convex/react'
import {
    Bookmark,
    Flag,
    Home,
    Landmark,
    List,
    LogOut,
    MessageCircle,
    Mic,
    Plus,
    RefreshCw,
    Trash2,
    User,
} from 'lucide-react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuGroup,
    DropdownMenuItem,
    DropdownMenuLabel,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import {
    Sidebar,
    SidebarContent,
    SidebarFooter,
    SidebarGroup,
    SidebarGroupContent,
    SidebarGroupLabel,
    SidebarHeader,
    SidebarInset,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
    SidebarProvider,
    SidebarTrigger,
} from '@/components/ui/sidebar'
import { useAuth, useUser } from '@/hooks/use-auth'
import type { Messages } from '@/lib/i18n'
import { useT } from '@/lib/i18n'
import { LanguageMenu } from './language-menu'

const NAV_ITEMS = [
    { to: '/', label: (t: Messages) => t.nav.home, icon: Home, end: true },
    {
        to: '/activity',
        label: (t: Messages) => t.nav.activity,
        icon: List,
        end: false,
    },
    {
        to: '/accounts',
        label: (t: Messages) => t.nav.accounts,
        icon: Landmark,
        end: false,
    },
    {
        to: '/insights',
        label: (t: Messages) => t.nav.insights,
        icon: Bookmark,
        end: false,
    },
] as const

function pathMatches(path: string, to: string, end: boolean) {
    return end ? path === to : path === to || path.startsWith(`${to}/`)
}

export function RootLayout() {
    const location = useLocation()
    const navigate = useNavigate()
    const auth = useAuth()
    const user = useUser()
    const t = useT()
    const isAdmin = useQuery(api.v1.featureFlags.queries.getMyAdminStatus)

    const currentTitle =
        NAV_ITEMS.find((item) =>
            pathMatches(location.pathname, item.to, item.end),
        )?.label(t) ??
        (location.pathname.startsWith('/add/manual')
            ? t.nav.addManually
            : location.pathname.startsWith('/add')
              ? t.nav.addWithGasti
              : t.common.appName)

    const initials = (user.name || user.email)
        .split(' ')
        .map((part) => part[0])
        .filter(Boolean)
        .slice(0, 2)
        .join('')
        .toUpperCase()

    return (
        <SidebarProvider>
            <Sidebar collapsible="icon">
                <SidebarHeader>
                    <div className="flex items-center gap-2 px-2 py-2">
                        <div className="flex size-8 items-center justify-center rounded-md bg-primary text-primary-foreground">
                            <span className="text-sm font-semibold">W</span>
                        </div>
                        <div className="flex flex-col group-data-[collapsible=icon]:hidden">
                            <span className="text-sm font-semibold">
                                {t.common.appName}
                            </span>
                            <span className="text-xs text-muted-foreground">
                                {t.nav.tagline}
                            </span>
                        </div>
                    </div>
                </SidebarHeader>

                <SidebarContent>
                    <SidebarGroup>
                        <SidebarGroupLabel>
                            {t.nav.navigation}
                        </SidebarGroupLabel>
                        <SidebarGroupContent>
                            <SidebarMenu>
                                {NAV_ITEMS.map((item) => {
                                    const isActive = pathMatches(
                                        location.pathname,
                                        item.to,
                                        item.end,
                                    )
                                    const Icon = item.icon
                                    const label = item.label(t)
                                    return (
                                        <SidebarMenuItem key={item.to}>
                                            <SidebarMenuButton
                                                tooltip={label}
                                                isActive={isActive}
                                                render={
                                                    <NavLink
                                                        to={item.to}
                                                        end={item.end}
                                                    />
                                                }
                                            >
                                                <Icon className="size-4" />
                                                <span>{label}</span>
                                            </SidebarMenuButton>
                                        </SidebarMenuItem>
                                    )
                                })}
                            </SidebarMenu>
                        </SidebarGroupContent>
                    </SidebarGroup>

                    <SidebarGroup>
                        <SidebarGroupLabel>{t.nav.actions}</SidebarGroupLabel>
                        <SidebarGroupContent>
                            <SidebarMenu>
                                <SidebarMenuItem>
                                    <SidebarMenuButton
                                        tooltip={t.nav.addWithGasti}
                                        isActive={pathMatches(
                                            location.pathname,
                                            '/add',
                                            true,
                                        )}
                                        render={<NavLink to="/add" />}
                                    >
                                        <span className="relative inline-flex size-4 items-center justify-center">
                                            <MessageCircle className="size-4" />
                                            <Mic className="absolute -right-1.5 -bottom-0.5 size-2.5" />
                                        </span>
                                        <span>{t.nav.addWithGasti}</span>
                                    </SidebarMenuButton>
                                </SidebarMenuItem>
                                <SidebarMenuItem>
                                    <SidebarMenuButton
                                        tooltip={t.nav.addManually}
                                        isActive={pathMatches(
                                            location.pathname,
                                            '/add/manual',
                                            false,
                                        )}
                                        render={<NavLink to="/add/manual" />}
                                    >
                                        <Plus className="size-4" />
                                        <span>{t.nav.addManually}</span>
                                    </SidebarMenuButton>
                                </SidebarMenuItem>
                            </SidebarMenu>
                        </SidebarGroupContent>
                    </SidebarGroup>
                </SidebarContent>

                <SidebarFooter>
                    <SidebarMenu>
                        <SidebarMenuItem>
                            <DropdownMenu>
                                <DropdownMenuTrigger
                                    render={
                                        <SidebarMenuButton
                                            size="lg"
                                            tooltip={user.name || user.email}
                                        />
                                    }
                                >
                                    <Avatar size="sm" className="rounded-md">
                                        {user.image ? (
                                            <AvatarImage src={user.image} />
                                        ) : null}
                                        <AvatarFallback className="rounded-md">
                                            {initials || (
                                                <User className="size-3" />
                                            )}
                                        </AvatarFallback>
                                    </Avatar>
                                    <div className="flex min-w-0 flex-col text-left">
                                        <span className="truncate text-sm font-medium">
                                            {user.name || t.common.account}
                                        </span>
                                        <span className="truncate text-xs text-muted-foreground">
                                            {user.email}
                                        </span>
                                    </div>
                                </DropdownMenuTrigger>
                                <DropdownMenuContent
                                    align="end"
                                    side="top"
                                    className="w-56"
                                >
                                    <DropdownMenuGroup>
                                        <DropdownMenuLabel>
                                            {user.name || user.email}
                                        </DropdownMenuLabel>
                                    </DropdownMenuGroup>
                                    {isAdmin && (
                                        <>
                                            <DropdownMenuSeparator />
                                            <DropdownMenuItem
                                                onClick={() =>
                                                    navigate(
                                                        '/admin/feature-flags',
                                                    )
                                                }
                                            >
                                                <Flag className="size-4" />
                                                Feature flags
                                            </DropdownMenuItem>
                                        </>
                                    )}
                                    <DropdownMenuSeparator />
                                    <LanguageMenu />
                                    <DropdownMenuSeparator />
                                    <DropdownMenuItem disabled>
                                        <RefreshCw className="size-4" />
                                        {t.nav.connectToAccount}
                                    </DropdownMenuItem>
                                    <DropdownMenuItem disabled>
                                        <Trash2 className="size-4" />
                                        {t.nav.deleteData}
                                    </DropdownMenuItem>
                                    <DropdownMenuSeparator />
                                    <DropdownMenuItem onClick={auth.signOut}>
                                        <LogOut className="size-4" />
                                        {t.nav.signOut}
                                    </DropdownMenuItem>
                                </DropdownMenuContent>
                            </DropdownMenu>
                        </SidebarMenuItem>
                    </SidebarMenu>
                </SidebarFooter>
            </Sidebar>

            <SidebarInset>
                <header className="sticky top-0 z-10 flex h-14 shrink-0 items-center gap-2 border-b bg-background px-4">
                    <SidebarTrigger />
                    <div className="h-4 w-px bg-border" aria-hidden />
                    <h1 className="text-sm font-medium">{currentTitle}</h1>
                </header>
                <div className="flex flex-1 flex-col">
                    <Outlet />
                </div>
            </SidebarInset>
        </SidebarProvider>
    )
}
