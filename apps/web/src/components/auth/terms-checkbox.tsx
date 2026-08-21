import { legalUrls } from '@wallet-bot/shared'
import { Checkbox } from 'actify'
import { useI18n, useT } from '@/lib/i18n'

/**
 * The affirmative-acceptance row for the legal documents: one combined
 * checkbox covering the 18+ requirement and both documents, the document
 * names linking to the published pages in the active locale
 * (docs/legal/README.md, implementation TODO #8).
 *
 * The sentence is NOT the checkbox label element: react-aria would toggle the
 * checkbox on any click inside a label, swallowing the links. The control
 * carries the full sentence as its accessible name instead, matching the
 * labelled-Switch rows in the filter sheet.
 */
export function TermsCheckbox({
    isSelected,
    onChange,
    isDisabled,
}: {
    isSelected: boolean
    onChange: (isSelected: boolean) => void
    isDisabled?: boolean
}) {
    const t = useT()
    const { locale } = useI18n()
    const urls = legalUrls(locale)
    const sentence = `${t.auth.termsAge18Prefix}${t.auth.termsLinkLabel}${t.auth.termsAnd}${t.auth.privacyLinkLabel}`

    return (
        <div className="flex items-center gap-1">
            <Checkbox
                aria-label={sentence}
                name="termsAccepted"
                value="accepted"
                isSelected={isSelected}
                onChange={onChange}
                isDisabled={isDisabled}
            />
            <span className="m3-body-medium text-on-surface">
                {t.auth.termsAge18Prefix}
                <a
                    href={urls.terms}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="font-semibold underline"
                >
                    {t.auth.termsLinkLabel}
                </a>
                {t.auth.termsAnd}
                <a
                    href={urls.privacy}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="font-semibold underline"
                >
                    {t.auth.privacyLinkLabel}
                </a>
            </span>
        </div>
    )
}
