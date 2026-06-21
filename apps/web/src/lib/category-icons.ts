import {
    Bus,
    Dumbbell,
    GraduationCap,
    Heart,
    HelpCircle,
    Home,
    type LucideIcon,
    PartyPopper,
    PawPrint,
    PiggyBank,
    ReceiptText,
    Shapes,
    ShoppingBag,
    ShoppingCart,
    Utensils,
} from 'lucide-react'
import type { IconOption } from './account-icons'

// Icon catalog for categories. Names mirror the native catalog
// (apps/native/lib/components/category_icons.dart) so a category keeps its icon
// across platforms.
export const CATEGORY_ICONS: readonly IconOption[] = [
    { name: 'category', Icon: Shapes },
    { name: 'receipt', Icon: ReceiptText },
    { name: 'shopping_bag', Icon: ShoppingBag },
    { name: 'shopping_cart', Icon: ShoppingCart },
    { name: 'savings', Icon: PiggyBank },
    { name: 'health', Icon: Heart },
    { name: 'education', Icon: GraduationCap },
    { name: 'restaurant', Icon: Utensils },
    { name: 'transport', Icon: Bus },
    { name: 'home', Icon: Home },
    { name: 'celebration', Icon: PartyPopper },
    { name: 'fitness', Icon: Dumbbell },
    { name: 'pets', Icon: PawPrint },
    { name: 'help', Icon: HelpCircle },
]

export const CATEGORY_DEFAULT_ICON = 'category'

export const CATEGORY_FALLBACK_ICON: LucideIcon = Shapes

export const CATEGORY_ICON_MAP: Record<string, LucideIcon> = Object.fromEntries(
    CATEGORY_ICONS.map((i) => [i.name, i.Icon]),
)
