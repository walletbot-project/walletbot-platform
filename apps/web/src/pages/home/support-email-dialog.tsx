import { Button, IconButton } from 'actify'
import { useState } from 'react'
import { DialogAction, M3Dialog } from '@/components/m3/dialog'
import { Icon } from '@/components/m3/icon'
import { useT } from '@/lib/i18n'
import { supportMailtoHref } from './support-email'

type SupportEmailDialogProps = {
    open: boolean
    onOpenChange: (open: boolean) => void
    /**
     * Whatever the user already typed in the feedback sheet. Carried into the
     * mail body so switching to email never costs them the text.
     */
    draft: string
}

/**
 * The escape hatch from the feedback sheet: the support mailbox, a button that
 * hands the draft to the user's mail client, and a copy button for when there
 * is no mail client to hand it to.
 */
export function SupportEmailDialog({
    open,
    onOpenChange,
    draft,
}: SupportEmailDialogProps) {
    const t = useT()
    // Shown in the dialog rather than as a toast: the confirmation belongs next
    // to the address it is about.
    const [copyState, setCopyState] = useState<'idle' | 'copied' | 'failed'>(
        'idle',
    )

    const address = t.feedback.supportEmail
    const footer = t.feedback.emailBodyFooter({ client: 'web' })

    const copy = async () => {
        try {
            await navigator.clipboard.writeText(address)
            setCopyState('copied')
        } catch (error) {
            console.error('copying the support address failed', error)
            setCopyState('failed')
        }
    }

    const openMailClient = () => {
        window.location.href = supportMailtoHref({
            address,
            subject: t.feedback.emailSubject,
            body: draft ? `${draft}\n\n${footer}` : footer,
        })
        onOpenChange(false)
    }

    return (
        <M3Dialog
            open={open}
            onOpenChange={(next) => {
                if (!next) setCopyState('idle')
                onOpenChange(next)
            }}
            icon="mail"
            title={t.feedback.emailTitle}
            description={t.feedback.emailBody}
            actions={
                <>
                    <DialogAction
                        label={t.common.close}
                        onPress={() => onOpenChange(false)}
                    />
                    <Button variant="filled" onPress={openMailClient}>
                        <Icon name="open_in_new" size={18} />
                        {t.feedback.emailOpen}
                    </Button>
                </>
            }
        >
            <div className="mt-4 flex items-center gap-2 rounded-xl bg-surface-container-highest py-1 pr-1 pl-3">
                {/* Selectable, so a failed clipboard write still leaves a way
                    to get the address out. */}
                <span className="m3-body-large min-w-0 flex-1 select-all truncate font-medium">
                    {address}
                </span>
                <IconButton
                    aria-label={t.feedback.emailCopy}
                    onPress={() => void copy()}
                    className="text-on-surface-variant"
                >
                    <Icon
                        name={copyState === 'copied' ? 'check' : 'content_copy'}
                    />
                </IconButton>
            </div>

            {copyState === 'idle' ? null : (
                <p
                    className={
                        copyState === 'copied'
                            ? 'm3-body-small mt-2 text-on-surface-variant'
                            : 'm3-body-small mt-2 text-error'
                    }
                >
                    {copyState === 'copied'
                        ? t.feedback.emailCopied
                        : t.feedback.emailCopyFailed}
                </p>
            )}
        </M3Dialog>
    )
}
