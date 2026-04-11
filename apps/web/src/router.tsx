import { createBrowserRouter } from 'react-router-dom'

import { AuthGuard } from '@/components/layout/auth-guard'
import { GlobalErrorBoundary } from '@/components/layout/error-boundary'
import { PublicGuard } from '@/components/layout/public-guard'
import { AuthLayout } from '@/layouts/auth-layout'
import { RootLayout } from '@/layouts/root-layout'

export const router = createBrowserRouter([
    {
        errorElement: <GlobalErrorBoundary />,
        children: [
            {
                path: '/live-demo',
                lazy: () =>
                    import('@/pages/live-demo').then((m) => ({
                        Component: m.LiveDemo,
                    })),
            },
            {
                path: '/live-demo-cloud',
                lazy: () =>
                    import('@/pages/live-demo-cloud').then((m) => ({
                        Component: m.LiveDemoCloud,
                    })),
            },
            {
                element: <PublicGuard />,
                children: [
                    {
                        element: <AuthLayout />,
                        children: [
                            {
                                path: '/login',
                                lazy: () =>
                                    import('@/pages/login').then((m) => ({
                                        Component: m.Login,
                                    })),
                            },
                        ],
                    },
                ],
            },
            {
                element: <AuthGuard />,
                children: [
                    {
                        element: <RootLayout />,
                        children: [
                            {
                                index: true,
                                lazy: () =>
                                    import('@/pages/home').then((m) => ({
                                        Component: m.Home,
                                    })),
                            },
                            {
                                path: '*',
                                lazy: () =>
                                    import('@/pages/not-found').then((m) => ({
                                        Component: m.NotFound,
                                    })),
                            },
                        ],
                    },
                ],
            },
        ],
    },
])
