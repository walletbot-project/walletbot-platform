import { type LegalDocument, legalDocumentUrl } from '@wallet-bot/shared'
import { Checkbox } from 'actify'

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

    const acceptTemplate =
        documents.length > 1
            ? t.legal.acceptBoth
            : documents[0] === 'privacy'
              ? t.legal.acceptPrivacy
              : t.legal.acceptTerms

    return (
        <div className="flex flex-col gap-1">
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
                <ConsentLabel template={acceptTemplate} />
            </Checkbox>
        </div>
    )
}

/** `[[terms]]` / `[[privacy]]`, as written in the message catalogs. */
const DOCUMENT_MARKER = /\[\[(terms|privacy)\]\]/

/**
 * The accept label with each document name as a link to its published text
 * (`apps/landing` serves them at `www.walletbot.live`).
 *
 * The links live inside the sentence rather than in a list under it: the panel
 * is short, and a separate "read X" row per document cost two lines. The
 * catalog keeps the marker form so each language can place the names — and its
 * own articles — where they belong.
 */
function ConsentLabel({ template }: { template: string }) {
    const t = useT()
    const { locale } = useI18n()

    return (
        <span className="m3-body-medium">
            {template
                .split(/(\[\[(?:terms|privacy)\]\])/)
                .map((part, index) => {
                    const marker = DOCUMENT_MARKER.exec(part)
                    if (!marker) return part
                    const document = marker[1] as LegalDocument
                    return (
                        <a
                            // biome-ignore lint/suspicious/noArrayIndexKey: the
                            // parts come from a fixed template, so their order and
                            // count never change between renders.
                            key={index}
                            href={legalDocumentUrl(document, locale)}
                            target="_blank"
                            rel="noreferrer"
                            // The label wraps the checkbox input, so a click here
                            // would toggle the box on the way out. Reading the
                            // terms must not tick the box that says you accept
                            // them.
                            onClick={(event) => event.stopPropagation()}
                            className="font-semibold underline underline-offset-2"
                        >
                            {document === 'terms'
                                ? t.legal.termsName
                                : t.legal.privacyName}
                        </a>
                    )
                })}
        </span>
    )
}
