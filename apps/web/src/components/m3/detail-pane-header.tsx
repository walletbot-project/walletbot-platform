import { IconButton } from 'actify'
import { useWindowSizeClass } from '@/hooks/use-window-size-class'
import { useT } from '@/lib/i18n'
import { AppBar } from './app-bar'
import { Icon } from './icon'

/**
 * The close bar an entity detail shows when it is embedded in the divided
 * view's pane: in the pane there is no route to pop and no drag handle, so it
 * offers an explicit close (native's `AccountDetailsSheet.build`).
 *
 * It is a real top app bar — same 64dp height and leading inset as every other
 * bar in the app, including the form pane's — so both pane occupants line up.
 *
 * Below the expanded breakpoint the detail is presented as a modal bottom
 * sheet, which already carries a drag handle, so nothing is rendered.
 */
export function DetailPaneHeader({ onClose }: { onClose: () => void }) {
    const t = useT()
    const inPane = useWindowSizeClass() === 'expanded'
    if (!inPane) return null
    return (
        <AppBar
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
