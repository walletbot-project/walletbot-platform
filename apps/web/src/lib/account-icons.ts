/**
 * An entry in an icon catalog: the stable name persisted on the entity, and
 * the Material Symbols glyph it renders as.
 */
export type IconOption = {
    /** Stable storage name, shared with the native app. */
    name: string
    /** Material Symbols ligature. */
    symbol: string
    /** Filled glyph — Flutter's `Icons.*_rounded` vs `Icons.*_outlined`. */
    filled: boolean
}

/**
 * Icon catalog for accounts. The backend stores the icon as a stable *name*
 * string; the UI renders a Material Symbols glyph. Names *and* glyphs mirror
 * the native catalog (apps/native/lib/components/account_icons.dart), so an
 * account looks the same on both platforms.
 */
export const ACCOUNT_ICONS: readonly IconOption[] = [
    { name: 'wallet', symbol: 'account_balance_wallet', filled: true },
    { name: 'bank', symbol: 'account_balance', filled: true },
    { name: 'savings', symbol: 'savings', filled: true },
    { name: 'cash', symbol: 'payments', filled: true },
    { name: 'card', symbol: 'credit_card', filled: true },
    { name: 'travel', symbol: 'flight_takeoff', filled: true },
    { name: 'investment', symbol: 'trending_up', filled: true },
    { name: 'money', symbol: 'attach_money', filled: true },
    { name: 'exchange', symbol: 'currency_exchange', filled: true },
    { name: 'real_estate', symbol: 'real_estate_agent', filled: true },
    { name: 'wallet_alt', symbol: 'wallet', filled: true },
]

export const ACCOUNT_DEFAULT_ICON = 'wallet'

export const ACCOUNT_FALLBACK_ICON: IconOption = ACCOUNT_ICONS[0]

const ACCOUNT_ICON_MAP: ReadonlyMap<string, IconOption> = new Map(
    ACCOUNT_ICONS.map((option) => [option.name, option]),
)

/** Resolves a stored icon name to its glyph, falling back to the default. */
export function accountIcon(name: string | undefined): IconOption {
    return (
        (name ? ACCOUNT_ICON_MAP.get(name) : undefined) ?? ACCOUNT_FALLBACK_ICON
    )
}
