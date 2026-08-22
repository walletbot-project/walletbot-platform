import { Button } from 'actify'
import type { ReactNode } from 'react'
import {
    DialogContent,
    DialogDescription,
    Dialog as DialogRoot,
    DialogTitle,
} from '@/components/ui/dialog'
import { cn } from '@/lib/utils'
import { Icon } from './icon'

/**
 * A dialog action. Material's dialogs use text buttons, and a destructive one
 * only recolours its label — `TextButton.styleFrom(foregroundColor: error)`.
 */
export function DialogAction({
    label,
    onPress,
    type = 'button',
    isDisabled = false,
    destructive = false,
    form,
}: {
    label: string
    onPress?: () => void
    type?: 'button' | 'submit'
    isDisabled?: boolean
    destructive?: boolean
    form?: string
}) {
    return (
        <Button
            variant="text"
            type={type}
            form={form}
            isDisabled={isDisabled}
            onPress={onPress}
            style={
                destructive
                    ? {
                          '--md-text-button-label-text-color':
                              'var(--md-sys-color-error)',
                          '--md-text-button-hover-label-text-color':
                              'var(--md-sys-color-error)',
                          '--md-text-button-focus-label-text-color':
                              'var(--md-sys-color-error)',
                          '--md-text-button-pressed-label-text-color':
                              'var(--md-sys-color-error)',
                      }
                    : undefined
            }
        >
            {label}
        </Button>
    )
}

type M3DialogProps = {
    open: boolean
    onOpenChange: (open: boolean) => void
    title: ReactNode
    /** Optional Material Symbols hero glyph, centred above the headline. */
    icon?: string
    /**
     * Supporting text. Pass a string for the plain one-paragraph case so it is
     * wired as the dialog's accessible description.
     */
    description?: string
    children?: ReactNode
    /** Trailing action row — text buttons, in Material's order (confirm last). */
    actions?: ReactNode
    className?: string
    /** Forwarded to the content wrapper, e.g. to submit a form on Enter. */
    onKeyDownCapture?: React.KeyboardEventHandler<HTMLDivElement>
}

/**
 * The Material 3 basic dialog, matching Flutter's `AlertDialog` under
 * `_DialogDefaultsM3`: a 28dp `surfaceContainerHigh` container at elevation 3,
 * a `headlineSmall` headline, `bodyMedium` supporting text in
 * `onSurfaceVariant`, and an end-aligned action row — with Material's 24dp
 * insets and 280–560dp width.
 *
 * Built on the shadcn dialog primitive (focus trap, scroll lock, portal) but
 * fully re-skinned, so nothing here inherits the shadcn look.
 */
export function M3Dialog({
    open,
    onOpenChange,
    title,
    icon,
    description,
    children,
    actions,
    className,
    onKeyDownCapture,
}: M3DialogProps) {
    return (
        <DialogRoot open={open} onOpenChange={onOpenChange}>
            <DialogContent
                showCloseButton={false}
                onKeyDownCapture={onKeyDownCapture}
                className={cn(
                    'flex max-h-[calc(100dvh-4rem)] min-w-70 flex-col gap-0 overflow-hidden rounded-[28px] bg-surface-container-high p-0 text-on-surface shadow-level-3 ring-0 sm:max-w-140',
                    className,
                )}
            >
                {icon ? (
                    <span className="flex justify-center pt-6 text-secondary">
                        <Icon name={icon} filled />
                    </span>
                ) : null}

                <DialogTitle
                    // The explicit `text-2xl/leading-8/font-normal` restate
                    // `m3-headline-small` in core utilities so tailwind-merge
                    // drops the primitive's own `text-base leading-none
                    // font-medium` — it can't dedupe a custom utility.
                    className={cn(
                        'm3-headline-small px-6 pt-6 font-normal text-2xl text-on-surface leading-8',
                        icon && 'pt-4 text-center',
                    )}
                >
                    {title}
                </DialogTitle>

                <div className="min-h-0 flex-1 overflow-y-auto px-6 pt-4 pb-6">
                    {description ? (
                        <DialogDescription className="m3-body-medium text-on-surface-variant">
                            {description}
                        </DialogDescription>
                    ) : null}
                    {children}
                </div>

                {actions ? (
                    <div className="flex flex-wrap items-center justify-end gap-2 px-6 pb-6">
                        {actions}
                    </div>
                ) : null}
            </DialogContent>
        </DialogRoot>
    )
}
