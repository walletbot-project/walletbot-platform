import { createBrowserRouter } from 'react-router-dom'

import { AuthGuard } from '@/components/layout/auth-guard'
import { GlobalErrorBoundary } from '@/components/layout/error-boundary'
import { PublicGuard } from '@/components/layout/public-guard'
import { AuthLayout } from '@/layouts/auth-layout'
import { RootLayout } from '@/layouts/root-layout'
import Home from './pages/home'
import { Login } from './pages/login'

export const router = createBrowserRouter([
    {
        errorElement: <GlobalErrorBoundary />,
        children: [
            {
                element: <PublicGuard />,
                children: [
                    {
                        element: <AuthLayout />,
                        children: [
                            {
                                path: '/login',
                                element: <Login mode="sign-in" />,
                            },
                            {
                                path: '/signup',
                                element: <Login mode="sign-up" />,
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
                                path: '/',
                                element: <Home />,
                            },
                            {
                                path: '/activity',
                                lazy: () =>
                                    import('@/pages/activity').then((m) => ({
                                        Component: m.Activity,
                                    })),
                            },
                            {
                                path: '/accounts',
                                lazy: () =>
                                    import('@/pages/accounts').then((m) => ({
                                        Component: m.Accounts,
                                    })),
                            },
                            {
                                path: '/insights',
                                lazy: () =>
                                    import('@/pages/insights').then((m) => ({
                                        Component: m.Insights,
                                    })),
                            },
                            {
                                path: '/add',
                                lazy: () =>
                                    import('@/pages/add').then((m) => ({
                                        Component: m.Add,
                                    })),
                            },
                            {
                                path: '/add/manual',
                                lazy: () =>
                                    import('@/pages/add-manual').then((m) => ({
                                        Component: m.AddManual,
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
