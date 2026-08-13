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
                // Deliberately guard-free: these pages are reached from email
                // links and must render whether or not a session exists —
                // PublicGuard would bounce a signed-in user to '/' and lose
                // the ?token/?error params.
                element: <AuthLayout />,
                children: [
                    {
                        path: '/forgot-password',
                        lazy: () =>
                            import('@/pages/forgot-password').then((m) => ({
                                Component: m.ForgotPassword,
                            })),
                    },
                    {
                        path: '/reset-password',
                        lazy: () =>
                            import('@/pages/reset-password').then((m) => ({
                                Component: m.ResetPassword,
                            })),
                    },
                    {
                        path: '/verify-email',
                        lazy: () =>
                            import('@/pages/verify-email').then((m) => ({
                                Component: m.VerifyEmail,
                            })),
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
                                path: '/admin/feature-flags',
                                lazy: () =>
                                    import('@/pages/admin/feature-flags').then(
                                        (m) => ({
                                            Component: m.FeatureFlags,
                                        }),
                                    ),
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
