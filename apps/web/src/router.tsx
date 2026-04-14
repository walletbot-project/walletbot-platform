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
                                element: <Login />,
                                /* lazy: () =>
                                    import('@/pages/login').then((m) => ({
                                        Component: m.Login,
                                    })), */
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
