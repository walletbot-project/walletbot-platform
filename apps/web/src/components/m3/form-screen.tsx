import { IconButton } from 'actify'
import type { ReactNode } from 'react'
import { useT } from '@/lib/i18n'
import { AppBar } from './app-bar'
import { Icon } from './icon'

type FormScreenProps = {
    /** Omitted when the form heads itself in its body, as the native
     * transaction form does. */
    title?: string
    onClose: () => void
    children: ReactNode
}

/**
 * The frame a creation form renders in — an app bar with a close action over a
 * scrolling body. It is the same node in the split pane and in the full-window
 * presentation, matching the native create screens, which are a `Scaffold`
 * either way (see `CreateAccountScreen`).
 */
export function FormScreen({ title, onClose, children }: FormScreenProps) {
    const t = useT()
    return (
        <>
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
            <div className="min-h-0 flex-1 overflow-y-auto">{children}</div>
        </>
    )
}
