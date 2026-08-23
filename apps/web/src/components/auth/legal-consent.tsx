import { type LegalDocument, legalDocumentUrl } from '@wallet-bot/shared'
import { Checkbox } from 'actify'

import { Icon } from '@/components/m3/icon'
import { useI18n, useT } from '@/lib/i18n'

/**
 * The two consent checks — 18+ and accepting the documents — shared by the
 * sign-up form and the acceptance gate, so both collect exactly the same
 * affirmative acceptance (docs/legal/README.md: browse-wrap is unenforceable
 * here).
 *
 * `documents` is what is being accepted right now: both on sign-up, and only
 * the ones that actually changed at the gate — accepting a document nobody
 * asked about would be recording consent that was never given.
 */
export function LegalConsentChecks({
    documents,
    ageConfirmed,
    accepted,
    onAgeConfirmedChange,
    onAcceptedChange,
    disabled = false,
}: {
    documents: readonly LegalDocument[]
    ageConfirmed: boolean
    accepted: boolean
    onAgeConfirmedChange: (value: boolean) => void
    onAcceptedChange: (value: boolean) => void
    disabled?: boolean
}) {
    const t = useT()

    const acceptLabel =
        documents.length > 1
            ? t.legal.acceptBoth
            : documents[0] === 'privacy'
              ? t.legal.acceptPrivacy
              : t.legal.acceptTerms

    return (
        <div className="flex flex-col gap-2">
            <Checkbox
                isSelected={ageConfirmed}
                onChange={onAgeConfirmedChange}
                isDisabled={disabled}
            >
                <span className="m3-body-medium">{t.legal.ageConfirm}</span>
            </Checkbox>
            <Checkbox
                isSelected={accepted}
                onChange={onAcceptedChange}
                isDisabled={disabled}
            >
                <span className="m3-body-medium">{acceptLabel}</span>
            </Checkbox>
            <LegalDocumentLinks documents={documents} />
        </div>
    )
}

/**
 * Links to the published documents (`apps/landing` renders `docs/legal/*.md`
 * at `www.walletbot.live`). They open in a new tab: a half-filled sign-up form
 * must survive reading the Terms.
 */
export function LegalDocumentLinks({
    documents,
}: {
    documents: readonly LegalDocument[]
}) {
    const t = useT()
    const { locale } = useI18n()

    return (
        <ul className="mt-1 flex flex-col gap-1">
            {documents.map((document) => (
                <li key={document}>
                    <a
                        href={legalDocumentUrl(document, locale)}
                        target="_blank"
                        rel="noreferrer"
                        className="m3-label-large inline-flex items-center gap-1 text-on-surface-variant underline underline-offset-4 hover:text-on-surface"
                    >
                        {document === 'terms'
                            ? t.legal.readTerms
                            : t.legal.readPrivacy}
                        <Icon name="open_in_new" size={16} />
                    </a>
                </li>
            ))}
        </ul>
    )
}
