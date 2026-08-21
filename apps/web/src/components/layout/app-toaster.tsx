import { Toaster } from '@/components/ui/sonner'
import { useTheme } from '@/lib/theme'

/**
 * The toast host, wired to the app's own theme controller.
 *
 * The shadcn `Toaster` resolves its theme through `next-themes`, which this app
 * does not use — light/dark lives in `ThemeProvider`, mirroring the native
 * app's `DisplaySettingsController`. Passing the resolved brightness keeps
 * toasts from following the OS when the user picked a theme explicitly.
 *
 * Toasts stand in for native's snackbars, so they take the snackbar's look
 * (`m3-snackbar`, in `styles/m3-theme.css`) and the bottom edge it rises from.
 * `cn-toast` is the hook the shadcn primitive puts on every toast; it is
 * repeated here because passing `toastOptions` replaces the primitive's rather
 * than merging with it.
 */
export function AppToaster() {
    const { brightness } = useTheme()
    return (
        <Toaster
            theme={brightness}
            position="bottom-center"
            toastOptions={{ classNames: { toast: 'cn-toast m3-snackbar' } }}
        />
    )
}
