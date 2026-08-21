import { api } from '@wallet-bot/backend/api'
import { IconButton } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { AppBar } from '@/components/m3/app-bar'
import { BottomSheet } from '@/components/m3/bottom-sheet'
import { GroupedCard } from '@/components/m3/grouped-card'
import { Icon } from '@/components/m3/icon'
import {
    type SelectionChoice,
    SelectionSheet,
} from '@/components/m3/selection-sheet'
import {
    Command,
    CommandEmpty,
    CommandGroup,
    CommandInput,
    CommandItem,
    CommandList,
} from '@/components/ui/command'
import { CURRENCY_CODES, currencyName } from '@/lib/currencies'
import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import {
    type LanguagePreference,
    useFormatLocale,
    useI18n,
    useT,
} from '@/lib/i18n'
import { type ThemePreference, useTheme } from '@/lib/theme'

type OpenSetting = 'language' | 'theme' | 'currency' | null

/**
 * Device and account preferences, mirroring the native settings screen
 * (apps/native/lib/screens/settings.dart): three grouped preference tiles,
 * each opening a single-choice bottom sheet.
 */
export function Settings() {
    const t = useT()
    const navigate = useNavigate()
    const [open, setOpen] = useState<OpenSetting>(null)

    const { preference: language, setPreference: setLanguage } = useI18n()
    const { preference: theme, setPreference: setTheme } = useTheme()

    const settings = useQuery(api.v1.users.queries.getSettings)
    const updateDefaultCurrency = useMutation(
        api.v1.users.mutations.updateDefaultCurrency,
    )

    const languageChoices: SelectionChoice<LanguagePreference>[] = [
        {
            value: 'system',
            icon: 'settings_suggest',
            label: t.settings.systemDefault,
        },
        { value: 'en', icon: 'language', label: t.settings.english },
        { value: 'es', icon: 'language', label: t.settings.spanish },
    ]

    const themeChoices: SelectionChoice<ThemePreference>[] = [
        {
            value: 'system',
            icon: 'brightness_auto',
            label: t.settings.systemDefault,
        },
        { value: 'light', icon: 'light_mode', label: t.settings.lightTheme },
        { value: 'dark', icon: 'dark_mode', label: t.settings.darkTheme },
    ]

    const languageLabel =
        languageChoices.find((choice) => choice.value === language)?.label ?? ''
    const themeLabel =
        themeChoices.find((choice) => choice.value === theme)?.label ?? ''

    const handleCurrency = (code: string) => {
        setOpen(null)
        // The toast handles both outcomes; re-awaiting the promise here only
        // re-threw the failure as an unhandled rejection.
        toast.promise(updateDefaultCurrency({ currency: code }), {
            loading: t.common.saving,
            success: t.common.saved,
            error: t.common.saveFailed,
        })
    }

    const tiles = [
        {
            key: 'language' as const,
            icon: 'language',
            title: t.settings.language,
            value: languageLabel,
        },
        {
            key: 'theme' as const,
            icon: 'palette',
            title: t.settings.theme,
            value: themeLabel,
        },
        {
            key: 'currency' as const,
            icon: 'attach_money',
            title: t.common.currency,
            value: settings?.defaultCurrency ?? '—',
        },
    ]

    return (
        <>
            <AppBar
                title={t.settings.title}
                leading={
                    <IconButton
                        aria-label={t.common.goBack}
                        onPress={() => navigate(-1)}
                        className="text-on-surface-variant"
                    >
                        <Icon name="arrow_back" />
                    </IconButton>
                }
            />
            <div className="min-h-0 flex-1 overflow-y-auto">
                <div
                    className="flex flex-col px-4 pt-2 pb-8"
                    style={{ gap: GROUP_SPACING }}
                >
                    {tiles.map((tile, index) => (
                        <GroupedCard
                            key={tile.key}
                            radius={groupedRadius(index, tiles.length)}
                            onClick={() => setOpen(tile.key)}
                        >
                            <div className="flex items-center gap-4 px-4 py-4">
                                <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-primary-container text-on-primary-container">
                                    <Icon name={tile.icon} filled size={22} />
                                </span>
                                <div className="flex min-w-0 flex-1 flex-col">
                                    <span className="m3-body-large truncate">
                                        {tile.title}
                                    </span>
                                    <span className="m3-body-small truncate text-on-surface-variant">
                                        {tile.value}
                                    </span>
                                </div>
                                <Icon
                                    name="chevron_right"
                                    filled
                                    className="text-on-surface-variant"
                                />
                            </div>
                        </GroupedCard>
                    ))}
                </div>
            </div>

            <SelectionSheet
                open={open === 'language'}
                onOpenChange={(next) => setOpen(next ? 'language' : null)}
                title={t.settings.language}
                description={t.settings.languageDescription}
                selected={language}
                choices={languageChoices}
                onSelect={(value) => {
                    setLanguage(value)
                    setOpen(null)
                }}
            />

            <SelectionSheet
                open={open === 'theme'}
                onOpenChange={(next) => setOpen(next ? 'theme' : null)}
                title={t.settings.theme}
                description={t.settings.themeDescription}
                selected={theme}
                choices={themeChoices}
                onSelect={(value) => {
                    setTheme(value)
                    setOpen(null)
                }}
            />

            <CurrencySheet
                open={open === 'currency'}
                onOpenChange={(next) => setOpen(next ? 'currency' : null)}
                selected={settings?.defaultCurrency}
                onSelect={handleCurrency}
            />
        </>
    )
}

function CurrencySheet({
    open,
    onOpenChange,
    selected,
    onSelect,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    selected: string | undefined
    onSelect: (code: string) => void
}) {
    const t = useT()
    const formatLocale = useFormatLocale()

    return (
        <BottomSheet
            open={open}
            onOpenChange={onOpenChange}
            title={t.common.currency}
            showTitle
        >
            <Command className="bg-transparent">
                <CommandInput placeholder={t.accounts.searchCurrency} />
                <CommandList className="max-h-none">
                    <CommandEmpty>{t.common.noResults}</CommandEmpty>
                    <CommandGroup>
                        {CURRENCY_CODES.map((code) => (
                            <CommandItem
                                key={code}
                                value={`${code} ${currencyName(code, formatLocale)}`}
                                onSelect={() => onSelect(code)}
                            >
                                <span className="w-12 font-medium">{code}</span>
                                <span className="flex-1 truncate text-on-surface-variant">
                                    {currencyName(code, formatLocale)}
                                </span>
                                {code === selected ? (
                                    <Icon
                                        name="check_circle"
                                        filled
                                        className="text-primary"
                                    />
                                ) : null}
                            </CommandItem>
                        ))}
                    </CommandGroup>
                </CommandList>
            </Command>
        </BottomSheet>
    )
}
