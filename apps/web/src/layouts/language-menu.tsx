import { Languages } from 'lucide-react'
import {
    DropdownMenuCheckboxItem,
    DropdownMenuSub,
    DropdownMenuSubContent,
    DropdownMenuSubTrigger,
} from '@/components/ui/dropdown-menu'
import { type LanguagePreference, useI18n, useT } from '@/lib/i18n'

/**
 * Language picker for the sidebar account menu. Mirrors the native app's
 * tri-state setting: an explicit locale, or `system` to follow the browser.
 * The choice is device-scoped (localStorage), so it does not follow the
 * account across devices.
 */
export function LanguageMenu() {
    const t = useT()
    const { preference, setPreference } = useI18n()

    const options: { value: LanguagePreference; label: string }[] = [
        { value: 'system', label: t.nav.languageSystem },
        { value: 'es', label: t.nav.languageSpanish },
        { value: 'en', label: t.nav.languageEnglish },
    ]

    return (
        <DropdownMenuSub>
            <DropdownMenuSubTrigger>
                <Languages className="size-4" />
                {t.nav.language}
            </DropdownMenuSubTrigger>
            <DropdownMenuSubContent>
                {options.map((option) => (
                    <DropdownMenuCheckboxItem
                        key={option.value}
                        checked={preference === option.value}
                        closeOnClick
                        onClick={() => setPreference(option.value)}
                    >
                        {option.label}
                    </DropdownMenuCheckboxItem>
                ))}
            </DropdownMenuSubContent>
        </DropdownMenuSub>
    )
}
