import {
    ArrowLeftRight,
    LayoutDashboard,
    Settings,
    Tag,
    Wallet,
} from 'lucide-react'
import { NavLink } from 'react-router-dom'
import { cn } from '@/lib/utils'

const TABS = [
    { icon: LayoutDashboard, path: '/', label: 'Home' },
    { icon: ArrowLeftRight, path: '/transactions', label: 'Txns' },
    { icon: Wallet, path: '/accounts', label: 'Accounts' },
    { icon: Tag, path: '/tags', label: 'Tags' },
    { icon: Settings, path: '/settings', label: 'Settings' },
] as const

export function MobileNav() {
    return (
        <nav className="fixed inset-x-0 bottom-0 z-50 border-t bg-background pb-[env(safe-area-inset-bottom)] md:hidden">
            <div className="flex h-14 items-center justify-around">
                {TABS.map((tab) => (
                    <NavLink
                        key={tab.path}
                        to={tab.path}
                        end={tab.path === '/'}
                        className={({ isActive }) =>
                            cn(
                                'flex flex-col items-center gap-0.5 px-3 py-1.5 text-[10px]',
                                isActive
                                    ? 'text-foreground'
                                    : 'text-muted-foreground',
                            )
                        }
                    >
                        <tab.icon className="size-5" />
                        <span>{tab.label}</span>
                    </NavLink>
                ))}
            </div>
        </nav>
    )
}
