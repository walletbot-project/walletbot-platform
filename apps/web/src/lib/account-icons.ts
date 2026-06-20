import {
    ArrowRightLeft,
    Banknote,
    Building2,
    CreditCard,
    DollarSign,
    Landmark,
    type LucideIcon,
    PiggyBank,
    PlaneTakeoff,
    TrendingUp,
    Wallet,
    WalletMinimal,
} from 'lucide-react'

export type IconOption = { name: string; Icon: LucideIcon }

// Icon catalog for accounts. The backend stores the icon as a stable *name*
// string; the UI renders a lucide glyph. Names mirror the native catalog
// (apps/native/lib/components/account_icons.dart) so an account keeps its icon
// across platforms.
export const ACCOUNT_ICONS: readonly IconOption[] = [
    { name: 'wallet', Icon: Wallet },
    { name: 'bank', Icon: Landmark },
    { name: 'savings', Icon: PiggyBank },
    { name: 'cash', Icon: Banknote },
    { name: 'card', Icon: CreditCard },
    { name: 'travel', Icon: PlaneTakeoff },
    { name: 'investment', Icon: TrendingUp },
    { name: 'money', Icon: DollarSign },
    { name: 'exchange', Icon: ArrowRightLeft },
    { name: 'real_estate', Icon: Building2 },
    { name: 'wallet_alt', Icon: WalletMinimal },
]

export const ACCOUNT_DEFAULT_ICON = 'wallet'

export const ACCOUNT_FALLBACK_ICON: LucideIcon = Wallet

export const ACCOUNT_ICON_MAP: Record<string, LucideIcon> = Object.fromEntries(
    ACCOUNT_ICONS.map((i) => [i.name, i.Icon]),
)
