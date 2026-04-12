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
                                    import('@/pages/dashboard').then((m) => ({
                                        Component: m.Dashboard,
                                    })),
                            },
                            {
                                path: 'transactions',
                                lazy: () =>
                                    import('@/pages/transactions').then(
                                        (m) => ({
                                            Component: m.Transactions,
                                        }),
                                    ),
                            },
                            {
                                path: 'accounts',
                                lazy: () =>
                                    import('@/pages/accounts').then((m) => ({
                                        Component: m.Accounts,
                                    })),
                            },
                            {
                                path: 'categories',
                                lazy: () =>
                                    import('@/pages/categories').then((m) => ({
                                        Component: m.Categories,
                                    })),
                            },
                            {
                                path: 'tags',
                                lazy: () =>
                                    import('@/pages/tags').then((m) => ({
                                        Component: m.Tags,
                                    })),
                            },
                            {
                                path: 'recurrences',
                                lazy: () =>
                                    import('@/pages/recurrences').then((m) => ({
                                        Component: m.Recurrences,
                                    })),
                            },
                            {
                                path: 'settings',
                                lazy: () =>
                                    import('@/pages/settings').then((m) => ({
                                        Component: m.Settings,
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
