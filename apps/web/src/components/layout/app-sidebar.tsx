import { t } from '@wallet-bot/shared'
import {
    ArrowLeftRight,
    Grid3x3,
    LayoutDashboard,
    LogOut,
    Repeat,
    Settings,
    Tag,
    Wallet,
} from 'lucide-react'
import { Link, useLocation } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import {
    Sidebar,
    SidebarContent,
    SidebarFooter,
    SidebarGroup,
    SidebarGroupContent,
    SidebarHeader,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
} from '@/components/ui/sidebar'
import { useAuth, useUser } from '@/hooks/use-auth'

const NAV_ITEMS = [
    { label: 'dashboard.title', icon: LayoutDashboard, path: '/' },
    {
        label: 'transactions.title',
        icon: ArrowLeftRight,
        path: '/transactions',
    },
    { label: 'accounts.title', icon: Wallet, path: '/accounts' },
    { label: 'categories.title', icon: Grid3x3, path: '/categories' },
    { label: 'tags.title', icon: Tag, path: '/tags' },
    { label: 'Recurring', icon: Repeat, path: '/recurrences', raw: true },
    { label: 'settings.title', icon: Settings, path: '/settings' },
] as const

export function AppSidebar() {
    const location = useLocation()
    const user = useUser()
    const { signOut } = useAuth()

    return (
        <Sidebar>
            <SidebarHeader className="px-4 py-3">
                <span className="text-lg font-semibold tracking-tight">
                    Wallet Bot
                </span>
            </SidebarHeader>
            <SidebarContent>
                <SidebarGroup>
                    <SidebarGroupContent>
                        <SidebarMenu>
                            {NAV_ITEMS.map((item) => {
                                const isActive =
                                    item.path === '/'
                                        ? location.pathname === '/'
                                        : location.pathname.startsWith(
                                              item.path,
                                          )
                                return (
                                    <SidebarMenuItem key={item.path}>
                                        <SidebarMenuButton
                                            render={<Link to={item.path} />}
                                            isActive={isActive}
                                        >
                                            <item.icon className="size-4" />
                                            <span>
                                                {'raw' in item
                                                    ? item.label
                                                    : t(item.label)}
                                            </span>
                                        </SidebarMenuButton>
                                    </SidebarMenuItem>
                                )
                            })}
                        </SidebarMenu>
                    </SidebarGroupContent>
                </SidebarGroup>
            </SidebarContent>
            <SidebarFooter className="px-4 py-3">
                <div className="flex items-center gap-3">
                    <div className="flex-1 truncate">
                        <p className="truncate text-sm font-medium">
                            {user.name}
                        </p>
                        <p className="truncate text-xs text-muted-foreground">
                            {user.email}
                        </p>
                    </div>
                    <Button
                        variant="ghost"
                        size="icon-sm"
                        onClick={() => signOut()}
                    >
                        <LogOut className="size-4" />
                    </Button>
                </div>
            </SidebarFooter>
        </Sidebar>
    )
}
