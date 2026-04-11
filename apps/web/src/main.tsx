import { ConvexBetterAuthProvider } from '@convex-dev/better-auth/react'
import { ConvexReactClient } from 'convex/react'
import React from 'react'
import ReactDOM from 'react-dom/client'
import { RouterProvider } from 'react-router-dom'
import { authClient } from '@/lib/auth-client'
import { router } from '@/router'
import './index.css'
import { Toaster } from './components/ui/sonner'
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
        expectAuth: false,
    },
)

ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
        <ConvexBetterAuthProvider client={convex} authClient={authClient}>
            <TooltipProvider>
                <RouterProvider router={router} />
            </TooltipProvider>
            <Toaster />
        </ConvexBetterAuthProvider>
    </React.StrictMode>,
)
