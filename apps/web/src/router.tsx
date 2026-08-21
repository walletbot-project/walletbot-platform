import { createBrowserRouter, Navigate } from 'react-router-dom'

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
                                children: [
                                    {
                                        // A child of '/' so Home stays mounted
                                        // underneath and the sheet overlays it,
                                        // rather than replacing the screen.
                                        // Being a route rather than component
                                        // state is what keeps a half-written
                                        // report alive across a resize
                                        // (LESSONS.md #13/#14).
                                        path: 'feedback',
                                        lazy: () =>
                                            import('@/pages/feedback').then(
                                                (m) => ({
                                                    Component: m.FeedbackRoute,
                                                }),
                                            ),
                                    },
                                ],
                            },
                            // Every view that is a screen — a list, a detail, a
                            // creation form — is a URL. Nothing about which of
                            // them is showing lives in component state, so
                            // reload, back/forward, deep links and window
                            // resizes all keep working for free. Only
                            // transient pickers (currency, icon, option
                            // sheets) stay as plain modals.
                            {
                                path: '/activity',
                                lazy: () =>
                                    import('@/pages/activity').then((m) => ({
                                        Component: m.Activity,
                                    })),
                                children: [
                                    {
                                        path: 'new',
                                        // A creation form is a page that
                                        // covers the window on small screens,
                                        // exactly as it always has been.
                                        handle: { fullScreen: true },
                                        lazy: () =>
                                            import('@/pages/activity').then(
                                                (m) => ({
                                                    Component:
                                                        m.TransactionCreateRoute,
                                                }),
                                            ),
                                    },
                                    {
                                        path: ':transactionId',
                                        // The transaction detail is a PAGE
                                        // below the split, not a sheet. The
                                        // native Activity screen presents it
                                        // as a real `MaterialPageRoute`
                                        // ("keeping the exact platform
                                        // transition, back button/gestures,
                                        // and route semantics" —
                                        // activity.dart:49). Only the account,
                                        // category and tag details are modals,
                                        // because those go through
                                        // `AdaptiveDetailView`, whose framing
                                        // is sheet/dialog/pane.
                                        handle: { fullScreen: true },
                                        lazy: () =>
                                            import('@/pages/activity').then(
                                                (m) => ({
                                                    Component:
                                                        m.TransactionDetailRoute,
                                                }),
                                            ),
                                    },
                                ],
                            },
                            {
                                path: '/accounts',
                                lazy: () =>
                                    import('@/pages/accounts').then((m) => ({
                                        Component: m.Accounts,
                                    })),
                                children: [
                                    {
                                        path: 'new',
                                        // A creation form is a page that
                                        // covers the window on small screens,
                                        // exactly as it always has been.
                                        handle: { fullScreen: true },
                                        lazy: () =>
                                            import('@/pages/accounts').then(
                                                (m) => ({
                                                    Component:
                                                        m.AccountCreateRoute,
                                                }),
                                            ),
                                    },
                                    {
                                        path: ':accountId',
                                        lazy: () =>
                                            import('@/pages/accounts').then(
                                                (m) => ({
                                                    Component:
                                                        m.AccountDetailRoute,
                                                }),
                                            ),
                                    },
                                ],
                            },
                            {
                                path: '/insights',
                                element: (
                                    <Navigate
                                        to="/insights/categories"
                                        replace
                                    />
                                ),
                            },
                            {
                                path: '/insights/:tab',
                                lazy: () =>
                                    import('@/pages/insights').then((m) => ({
                                        Component: m.Insights,
                                    })),
                                children: [
                                    {
                                        path: 'new',
                                        // A creation form is a page that
                                        // covers the window on small screens,
                                        // exactly as it always has been.
                                        handle: { fullScreen: true },
                                        lazy: () =>
                                            import('@/pages/insights').then(
                                                (m) => ({
                                                    Component:
                                                        m.InsightCreateRoute,
                                                }),
                                            ),
                                    },
                                    {
                                        path: ':entityId',
                                        lazy: () =>
                                            import('@/pages/insights').then(
                                                (m) => ({
                                                    Component:
                                                        m.InsightDetailRoute,
                                                }),
                                            ),
                                    },
                                ],
                            },
                            {
                                path: '/add',
                                lazy: () =>
                                    import('@/pages/add').then((m) => ({
                                        Component: m.Add,
                                    })),
                            },
                            {
                                path: '/settings',
                                lazy: () =>
                                    import('@/pages/settings').then((m) => ({
                                        Component: m.Settings,
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
