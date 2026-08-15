import { Toaster } from '@/components/ui/sonner'
import { useTheme } from '@/lib/theme'

/**
 * The toast host, wired to the app's own theme controller.
 *
 * The shadcn `Toaster` resolves its theme through `next-themes`, which this app
 * does not use — light/dark lives in `ThemeProvider`, mirroring the native
 * app's `DisplaySettingsController`. Passing the resolved brightness keeps
 * toasts from following the OS when the user picked a theme explicitly.
 */
export function AppToaster() {
    const { brightness } = useTheme()
    return <Toaster theme={brightness} />
}
