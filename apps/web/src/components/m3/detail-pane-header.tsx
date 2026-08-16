import { IconButton } from 'actify'
import { useWindowSizeClass } from '@/hooks/use-window-size-class'
import { useT } from '@/lib/i18n'
import { AppBar } from './app-bar'
import { Icon } from './icon'

/**
 * The app bar an entity detail shows when it is not presented as a bottom
 * sheet: in the divided view's pane, and in the dialog framing between the
 * sheet and split breakpoints. Neither has a route to pop or a drag handle, so
 * the bar carries the entity-type title and an explicit close (native's
 * `AccountDetailsSheet.build` in its `onClose != null` branch).
 *
 * It is a real top app bar — same height and leading inset as every other bar
 * in the app, the list column's included — which is what lines the two columns
 * of the divided view up.
 *
 * On compact windows the detail is a modal bottom sheet, which already carries
 * a drag handle, so nothing is rendered.
 */
export function DetailPaneHeader({
    title,
    onClose,
}: {
    title: string
    onClose: () => void
}) {
    const t = useT()
    const inSheet = useWindowSizeClass() === 'compact'
    if (inSheet) return null
    return (
        <AppBar
            title={title}
            leading={
                <IconButton
                    aria-label={t.common.close}
                    onPress={onClose}
                    className="text-on-surface-variant"
                >
                    <Icon name="close" />
                </IconButton>
            }
        />
    )
}
