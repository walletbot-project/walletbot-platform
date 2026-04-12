import { Outlet } from 'react-router-dom'
import { AppSidebar } from '@/components/layout/app-sidebar'
import { MobileNav } from '@/components/layout/mobile-nav'
import { VoiceFab } from '@/components/shared/voice-fab'
import { Separator } from '@/components/ui/separator'
import {
    SidebarInset,
    SidebarProvider,
    SidebarTrigger,
} from '@/components/ui/sidebar'

export function RootLayout() {
    return (
        <SidebarProvider>
            <AppSidebar />
            <SidebarInset>
                <header className="flex h-12 shrink-0 items-center gap-2 border-b px-4 md:px-6">
                    <SidebarTrigger className="-ml-1" />
                    <Separator orientation="vertical" className="mr-2 h-4!" />
                    <span className="text-sm font-medium text-muted-foreground">
                        Wallet Bot
                    </span>
                </header>
                <main className="flex-1 overflow-auto p-4 pb-20 md:p-6 md:pb-6">
                    <Outlet />
                </main>
            </SidebarInset>
            <MobileNav />
            <VoiceFab />
        </SidebarProvider>
    )
}
