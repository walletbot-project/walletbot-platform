import {
    BarChart3,
    Bot,
    Home,
    Landmark,
    List,
    LogOut,
    Plus,
    RefreshCw,
    Trash2,
    User,
} from 'lucide-react'
import { NavLink, Outlet, useLocation } from 'react-router-dom'
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

const NAV_ITEMS = [
    { to: '/', label: 'Home', icon: Home, end: true },
    { to: '/activity', label: 'Activity', icon: List, end: false },
    { to: '/accounts', label: 'Cuentas', icon: Landmark, end: false },
    { to: '/insights', label: 'Insights', icon: BarChart3, end: false },
] as const

function pathMatches(path: string, to: string, end: boolean) {
    return end ? path === to : path === to || path.startsWith(`${to}/`)
}

export function RootLayout() {
    const location = useLocation()
    const auth = useAuth()
    const user = useUser()

    const currentTitle =
        NAV_ITEMS.find((item) =>
            pathMatches(location.pathname, item.to, item.end),
        )?.label ??
        (location.pathname.startsWith('/add/manual')
            ? 'Añadir manualmente'
            : location.pathname.startsWith('/add')
              ? 'Añadir con Gasti'
              : 'Wallet Bot')

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
                                Wallet Bot
                            </span>
                            <span className="text-xs text-muted-foreground">
                                Personal finance
                            </span>
                        </div>
                    </div>
                </SidebarHeader>

                <SidebarContent>
                    <SidebarGroup>
                        <SidebarGroupLabel>Navigation</SidebarGroupLabel>
                        <SidebarGroupContent>
                            <SidebarMenu>
                                {NAV_ITEMS.map((item) => {
                                    const isActive = pathMatches(
                                        location.pathname,
                                        item.to,
                                        item.end,
                                    )
                                    const Icon = item.icon
                                    return (
                                        <SidebarMenuItem key={item.to}>
                                            <SidebarMenuButton
                                                tooltip={item.label}
                                                isActive={isActive}
                                                render={
                                                    <NavLink
                                                        to={item.to}
                                                        end={item.end}
                                                    />
                                                }
                                            >
                                                <Icon className="size-4" />
                                                <span>{item.label}</span>
                                            </SidebarMenuButton>
                                        </SidebarMenuItem>
                                    )
                                })}
                            </SidebarMenu>
                        </SidebarGroupContent>
                    </SidebarGroup>

                    <SidebarGroup>
                        <SidebarGroupLabel>Actions</SidebarGroupLabel>
                        <SidebarGroupContent>
                            <SidebarMenu>
                                <SidebarMenuItem>
                                    <SidebarMenuButton
                                        tooltip="Añadir con Gasti"
                                        isActive={pathMatches(
                                            location.pathname,
                                            '/add',
                                            true,
                                        )}
                                        render={<NavLink to="/add" />}
                                    >
                                        <Bot className="size-4" />
                                        <span>Añadir con Gasti</span>
                                    </SidebarMenuButton>
                                </SidebarMenuItem>
                                <SidebarMenuItem>
                                    <SidebarMenuButton
                                        tooltip="Añadir manualmente"
                                        isActive={pathMatches(
                                            location.pathname,
                                            '/add/manual',
                                            false,
                                        )}
                                        render={<NavLink to="/add/manual" />}
                                    >
                                        <Plus className="size-4" />
                                        <span>Añadir manualmente</span>
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
                                            {user.name || 'Account'}
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
                                    <DropdownMenuSeparator />
                                    <DropdownMenuItem disabled>
                                        <RefreshCw className="size-4" />
                                        Connect to account
                                    </DropdownMenuItem>
                                    <DropdownMenuItem disabled>
                                        <Trash2 className="size-4" />
                                        Delete data
                                    </DropdownMenuItem>
                                    <DropdownMenuSeparator />
                                    <DropdownMenuItem onClick={auth.signOut}>
                                        <LogOut className="size-4" />
                                        Sign out
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
