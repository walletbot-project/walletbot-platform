import { ACCOUNT_FALLBACK_ICON, ACCOUNT_ICON_MAP } from '@/lib/account-icons'

/** Renders an account's glyph by its stored name, falling back to the default. */
export function AccountIcon({
    name,
    className,
    color,
}: {
    name?: string
    className?: string
    color?: string
}) {
    const Glyph =
        (name ? ACCOUNT_ICON_MAP[name] : undefined) ?? ACCOUNT_FALLBACK_ICON
    return <Glyph className={className} style={color ? { color } : undefined} />
}
