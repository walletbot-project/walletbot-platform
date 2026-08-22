import { Button, CircularProgress, TextField } from 'actify'
import type { ComponentProps, ReactNode } from 'react'
import { AuthBackdrop } from '@/components/auth/auth-backdrop'
import { Icon } from '@/components/m3/icon'
import { useT } from '@/lib/i18n'

/**
 * The auth screens' page frame, porting the native login `Scaffold`: the
 * painted backdrop under a 480px column. Web centres that column in the
 * viewport instead of pinning it to the top, and falls back to top-aligned
 * scrolling once the panel is taller than the window.
 */
export function AuthScaffold({ children }: { children: ReactNode }) {
    return (
        <div className="relative flex min-h-dvh flex-col overflow-y-auto px-5 py-7">
            <AuthBackdrop />
            <div className="mx-auto my-auto flex w-full max-w-120 flex-col">
                {children}
            </div>
        </div>
    )
}

/**
 * The product lockup at the top of every auth screen, porting `_HeroHeader`.
 */
export function AuthHeroHeader({ subtitle }: { subtitle: string }) {
    const t = useT()
    return (
        <div className="flex items-center gap-3.5">
            <span className="flex size-14 shrink-0 items-center justify-center rounded-[18px] bg-primary text-on-primary shadow-[0_12px_22px_color-mix(in_srgb,var(--md-sys-color-primary)_26%,transparent)]">
                <Icon name="account_balance_wallet" filled />
            </span>
            <div className="flex min-w-0 flex-col">
                <h1 className="m3-headline-medium font-black leading-none">
                    {t.common.appName}
                </h1>
                <p className="m3-body-medium mt-1 font-semibold text-on-surface-variant">
                    {subtitle}
                </p>
            </div>
        </div>
    )
}

/**
 * Scaffold + hero + the panel column — the frame every auth screen shares
 * (login, signup, forgot, reset, verify), all under the same hero subtitle.
 */
export function AuthFrame({ children }: { children: ReactNode }) {
    const t = useT()
    return (
        <AuthScaffold>
            <AuthHeroHeader subtitle={t.auth.signInToContinue} />
            <div className="mt-5.5">{children}</div>
        </AuthScaffold>
    )
}

/** The translucent card the auth flows live in, porting `_Panel`. */
export function AuthPanel({ children }: { children: ReactNode }) {
    return <div className="auth-panel flex flex-col p-4.5">{children}</div>
}

/**
 * A message-only panel — icon, headline, copy and one primary action. The
 * shape of every terminal auth state (link sent, link dead, email verified).
 */
export function AuthMessagePanel({
    icon,
    title,
    subtitle,
    actionLabel,
    onAction,
    children,
}: {
    icon: string
    title: string
    subtitle: string
    actionLabel: string
    onAction: () => void
    /** Optional extra copy between the title and the action. */
    children?: ReactNode
}) {
    return (
        <AuthPanel>
            <AuthPanelTitle icon={icon} title={title} subtitle={subtitle} />
            {children}
            <div className="mt-4">
                <AuthPrimaryButton
                    submitting={false}
                    label={actionLabel}
                    onPress={onAction}
                />
            </div>
        </AuthPanel>
    )
}

/** The inline error strip under an auth form's fields. */
export function AuthErrorNote({ message }: { message: string }) {
    return (
        <p className="m3-body-medium rounded-2xl bg-error-container px-3 py-2 text-on-error-container">
            {message}
        </p>
    )
}

/** A panel's leading icon tile + headline + one-line subtitle (`_PanelTitle`). */
export function AuthPanelTitle({
    icon,
    title,
    subtitle,
}: {
    icon: string
    title: string
    subtitle: string
}) {
    return (
        <div className="flex items-center gap-3">
            <span className="flex size-10.5 shrink-0 items-center justify-center rounded-[14px] bg-primary-container text-on-primary-container">
                <Icon name={icon} filled size={22} />
            </span>
            <div className="flex min-w-0 flex-col">
                <h2 className="m3-title-medium font-black">{title}</h2>
                <p className="m3-body-small mt-0.5 font-semibold leading-tight text-on-surface-variant">
                    {subtitle}
                </p>
            </div>
        </div>
    )
}

/**
 * The 54px, 16dp-shaped primary action the native panels use instead of the
 * default M3 pill.
 */
export function AuthPrimaryButton({
    label,
    submitting,
    type = 'button',
    onPress,
}: {
    label: string
    submitting: boolean
    type?: 'button' | 'submit'
    onPress?: () => void
}) {
    return (
        <Button
            type={type}
            variant="filled"
            className="w-full"
            style={{
                height: 54,
                '--md-filled-button-container-shape': '16px',
            }}
            isDisabled={submitting}
            onPress={onPress}
        >
            {submitting ? (
                <CircularProgress isIndeterminate size="xs" />
            ) : (
                label
            )}
        </Button>
    )
}

type AuthTextFieldProps = Omit<
    ComponentProps<typeof TextField>,
    'variant' | 'leadingIcon' | 'className'
> & {
    /** Material Symbols ligature for the field's prefix glyph. */
    icon: string
}

/** The login flows' text field, porting `_LoginTextField`. */
export function AuthTextField({ icon, ...props }: AuthTextFieldProps) {
    return (
        <TextField
            {...props}
            variant="outlined"
            className="auth-field w-full"
            leadingIcon={
                <Icon
                    name={icon}
                    size={20}
                    className="text-on-surface-variant"
                />
            }
        />
    )
}

/** The `or` rule between the email form and the Google action. */
export function AuthOrDivider({ label }: { label: string }) {
    return (
        <div className="flex items-center gap-3">
            <span className="h-px flex-1 bg-outline-variant" />
            <span className="m3-label-medium font-bold text-on-surface-variant">
                {label}
            </span>
            <span className="h-px flex-1 bg-outline-variant" />
        </div>
    )
}
