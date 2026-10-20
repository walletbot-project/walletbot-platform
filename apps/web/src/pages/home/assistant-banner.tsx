import { IconButton } from 'actify'
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { AgentGlyph } from '@/components/m3/agent-glyph'
import { Icon } from '@/components/m3/icon'
import { useT } from '@/lib/i18n'

const STORAGE_KEY = 'assistant_banner_dismissed'

function readDismissed(): boolean {
    try {
        return localStorage.getItem(STORAGE_KEY) === '1'
    } catch {
        return false
    }
}

function writeDismissed(): void {
    try {
        localStorage.setItem(STORAGE_KEY, '1')
    } catch {
        // Restricted storage only means the banner comes back next visit.
    }
}

/**
 * Home invitation to try the assistant, mirroring native's `AssistantBanner`
 * (apps/native/lib/components/assistant_banner.dart). Only the close button
 * hides it for good, and only in this browser.
 */
export function AssistantBanner() {
    const t = useT()
    const navigate = useNavigate()
    const [dismissed, setDismissed] = useState(readDismissed)

    if (dismissed) return null

    const dismiss = () => {
        writeDismissed()
        setDismissed(true)
    }

    return (
        <section className="relative mb-4 overflow-hidden rounded-3xl bg-primary-container p-5 text-on-primary-container">
            <span
                aria-hidden="true"
                className="pointer-events-none absolute -top-[70px] -right-[50px] size-[200px] rounded-full bg-white/18"
            />

            <div className="relative flex flex-col items-start">
                <div className="flex items-center gap-3 pr-9">
                    <span className="flex size-11 shrink-0 items-center justify-center rounded-full bg-on-primary-container text-primary-container">
                        <AgentGlyph size={24} />
                    </span>
                    <h2 className="m3-title-large font-black">
                        {t.assistantBanner.title}
                    </h2>
                </div>
                <div className="mt-4 flex max-w-[360px] items-center gap-2 rounded-[18px] rounded-bl-[4px] bg-white/60 py-2.5 pr-3.5 pl-3">
                    <Icon name="mic" filled size={18} />
                    <span className="m3-body-medium font-semibold">
                        {t.assistantBanner.message}
                    </span>
                </div>
                <button
                    type="button"
                    onClick={() => navigate('/add')}
                    className="m3-label-large m3-state-layer mt-4 flex h-12 w-full cursor-pointer items-center justify-center rounded-full bg-on-primary-container px-6 text-white"
                >
                    {t.assistantBanner.action}
                </button>
            </div>

            <div className="absolute top-[22px] right-3">
                <IconButton
                    aria-label={t.common.close}
                    onPress={dismiss}
                    className="text-on-primary-container"
                >
                    <Icon name="close" />
                </IconButton>
            </div>
        </section>
    )
}
