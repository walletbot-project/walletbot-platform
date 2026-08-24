import { ConvexBetterAuthProvider } from '@convex-dev/better-auth/react'
import { ConvexReactClient } from 'convex/react'
import React from 'react'
import ReactDOM from 'react-dom/client'
import { RouterProvider } from 'react-router-dom'
import { AppToaster } from '@/components/layout/app-toaster'
import { I18nProvider } from '@/components/layout/i18n-provider'
import { ThemeProvider } from '@/components/layout/theme-provider'
import { authClient } from '@/lib/auth-client'
import { router } from '@/router'
import './index.css'
import { TooltipProvider } from './components/ui/tooltip'

// Auto-reload on stale chunk errors after deployment.
// Uses sessionStorage to prevent infinite reload loops.
window.addEventListener('vite:preloadError', () => {
    const lastReload = sessionStorage.getItem('chunk-reload')
    if (!lastReload || Date.now() - Number(lastReload) > 10_000) {
        sessionStorage.setItem('chunk-reload', String(Date.now()))
        window.location.reload()
    }
})

const convex = new ConvexReactClient(
    import.meta.env.VITE_CONVEX_URL as string,
    {
        expectAuth: true,
    },
)

ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
        <ConvexBetterAuthProvider client={convex} authClient={authClient}>
            <ThemeProvider>
                <I18nProvider>
                    <TooltipProvider>
                        <RouterProvider router={router} />
                    </TooltipProvider>
                    <AppToaster />
                </I18nProvider>
            </ThemeProvider>
        </ConvexBetterAuthProvider>
    </React.StrictMode>,
)
