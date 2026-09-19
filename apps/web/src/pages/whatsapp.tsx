import { api } from '@wallet-bot/backend/api'
import { Button, IconButton } from 'actify'
import { useMutation, useQuery } from 'convex/react'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { AppBar } from '@/components/m3/app-bar'
import { DialogAction, M3Dialog } from '@/components/m3/dialog'
import { GroupedCard } from '@/components/m3/grouped-card'
import { Icon } from '@/components/m3/icon'
import { Skeleton } from '@/components/ui/skeleton'
import { GROUP_SPACING, groupedRadius } from '@/lib/grouped-list'
import { useFormatLocale, useT } from '@/lib/i18n'

type LinkCode = {
    code: string
    expiresAt: number
    deepLink: string | null
}

/**
 * Connect or disconnect the user's WhatsApp number, mirroring the native
 * screen (`apps/native/lib/screens/whatsapp_link.dart`): the same backend
 * calls, the same states, the same copy.
 *
 * Nothing is cached, on purpose. Link state is only read on a screen that
 * cannot act without the network, and a cached code would be a stale
 * credential — the code is what grants a phone number access to this account.
 *
 * Reachability is the one deliberate difference from the account menu that
 * points here: the row is hidden for accounts outside the `whatsapp` rollout,
 * but the route stays open, so someone whose flag was switched off after
 * linking can still reach this page and disconnect their number.
 */
export function Whatsapp() {
    const t = useT()
    const navigate = useNavigate()
    const formatLocale = useFormatLocale()

    const status = useQuery(api.v1.whatsapp.queries.linkStatus)
    const createLinkCode = useMutation(api.v1.whatsapp.mutations.createLinkCode)
    const unlink = useMutation(api.v1.whatsapp.mutations.unlink)

    const [code, setCode] = useState<LinkCode | null>(null)
    const [busy, setBusy] = useState(false)
    // The number a confirmation is open for, or null when none is.
    const [confirming, setConfirming] = useState<string | null>(null)

    // Drop the code the moment it expires, so the screen never shows one the
    // backend would reject. One timer, armed per code — the native controller
    // does the same rather than ticking.
    useEffect(() => {
        if (code === null) return
        const remaining = code.expiresAt - Date.now()
        if (remaining <= 0) {
            setCode(null)
            return
        }
        const timer = setTimeout(() => setCode(null), remaining)
        return () => clearTimeout(timer)
    }, [code])

    const handleCreate = async () => {
        setBusy(true)
        try {
            const minted = await createLinkCode({})
            setCode({
                code: minted.code,
                expiresAt: minted.expiresAt,
                deepLink: minted.deepLink,
            })
        } catch {
            toast.error(t.whatsapp.codeFailed)
        } finally {
            setBusy(false)
        }
    }

    const handleCopy = async (value: string) => {
        try {
            await navigator.clipboard.writeText(value)
            toast.success(t.whatsapp.codeCopied)
        } catch {
            // Clipboard access is denied outside a secure context and in some
            // embedded browsers. The code is selectable on screen, so say that
            // instead of failing silently.
            toast.error(t.whatsapp.copyFailed)
        }
    }

    const handleOpen = (deepLink: string) => {
        // The deep link is what keeps this flow user-initiated: it opens
        // WhatsApp with the code already typed, so the user's own send opens
        // the 24h service window. Wallet Bot never messages first.
        const opened = window.open(deepLink, '_blank', 'noopener,noreferrer')
        if (opened === null) toast.error(t.whatsapp.openFailed)
    }

    const handleUnlink = async (waId: string) => {
        setConfirming(null)
        setBusy(true)
        try {
            await unlink({ waId })
            // Unlinking revokes pending codes server-side, so drop ours too
            // rather than leaving one on screen that can no longer link.
            setCode(null)
            toast.success(t.whatsapp.disconnected)
        } catch {
            toast.error(t.whatsapp.disconnectFailed)
        } finally {
            setBusy(false)
        }
    }

    const numbers = status?.numbers ?? []
    const isLinked = numbers.length > 0
    // Read out of the state object so the null check narrows for the handler
    // below; a deployment with no business number mints codes without one.
    const deepLink = code?.deepLink ?? null

    return (
        <>
            <AppBar
                title={t.whatsapp.title}
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
                <div className="flex flex-col px-4 pt-2 pb-8">
                    {status === undefined ? (
                        <StatusSkeleton />
                    ) : !status.available && !isLinked ? (
                        <MessageCard
                            icon="block"
                            title={t.whatsapp.unavailableTitle}
                            body={t.whatsapp.unavailableBody}
                        />
                    ) : isLinked ? (
                        <>
                            <MessageCard
                                icon="check_circle"
                                title={t.whatsapp.connectedTitle}
                                body={t.whatsapp.connectedBody}
                            />
                            <div
                                className="mt-6 flex flex-col"
                                style={{ gap: GROUP_SPACING }}
                            >
                                {numbers.map((number, index) => (
                                    <GroupedCard
                                        key={number.waId}
                                        radius={groupedRadius(
                                            index,
                                            numbers.length,
                                        )}
                                    >
                                        <div className="flex items-center gap-3 px-4 py-3">
                                            <div className="flex min-w-0 flex-1 flex-col">
                                                {/* `+` prefixed for reading
                                                    only. The stored identity is
                                                    the raw wa_id and is never
                                                    rebuilt from a formatted
                                                    number. */}
                                                <span className="m3-body-large truncate">
                                                    +{number.waId}
                                                </span>
                                                {number.linkedAt ===
                                                null ? null : (
                                                    <span className="m3-body-small truncate text-on-surface-variant">
                                                        {t.whatsapp.linkedOn({
                                                            date: new Date(
                                                                number.linkedAt,
                                                            ).toLocaleDateString(
                                                                formatLocale,
                                                                {
                                                                    day: 'numeric',
                                                                    month: 'long',
                                                                    year: 'numeric',
                                                                },
                                                            ),
                                                        })}
                                                    </span>
                                                )}
                                            </div>
                                            <Button
                                                type="button"
                                                variant="text"
                                                isDisabled={busy}
                                                onPress={() =>
                                                    setConfirming(number.waId)
                                                }
                                            >
                                                {t.whatsapp.disconnect}
                                            </Button>
                                        </div>
                                    </GroupedCard>
                                ))}
                            </div>
                        </>
                    ) : (
                        <>
                            <MessageCard
                                icon="chat_bubble"
                                title={t.whatsapp.notConnectedTitle}
                                body={t.whatsapp.notConnectedBody}
                            />
                            {code === null ? (
                                <div className="mt-6 flex">
                                    <Button
                                        type="button"
                                        variant="filled"
                                        isDisabled={busy}
                                        onPress={() => void handleCreate()}
                                    >
                                        {t.whatsapp.connect}
                                    </Button>
                                </div>
                            ) : (
                                <>
                                    <GroupedCard
                                        radius={groupedRadius(0, 1)}
                                        className="mt-6"
                                    >
                                        <div className="flex flex-col p-5">
                                            <span className="m3-body-small text-on-surface-variant">
                                                {t.whatsapp.codeLabel}
                                            </span>
                                            {/* Selectable, so the code is
                                                still copyable by hand when the
                                                clipboard API is unavailable. */}
                                            <span className="m3-headline-medium mt-2 select-all font-bold tabular-nums tracking-[0.25em]">
                                                {code.code}
                                            </span>
                                            <span className="m3-body-small mt-2 text-on-surface-variant">
                                                {t.whatsapp.codeExpiryHint}
                                            </span>
                                        </div>
                                    </GroupedCard>
                                    <div className="mt-4 flex flex-wrap gap-2">
                                        {deepLink === null ? null : (
                                            <Button
                                                type="button"
                                                variant="filled"
                                                onPress={() =>
                                                    handleOpen(deepLink)
                                                }
                                            >
                                                {t.whatsapp.openWhatsapp}
                                            </Button>
                                        )}
                                        <Button
                                            type="button"
                                            variant="outlined"
                                            onPress={() =>
                                                void handleCopy(code.code)
                                            }
                                        >
                                            {t.whatsapp.copyCode}
                                        </Button>
                                        <Button
                                            type="button"
                                            variant="text"
                                            onPress={() => setCode(null)}
                                        >
                                            {t.common.cancel}
                                        </Button>
                                    </div>
                                </>
                            )}
                        </>
                    )}
                </div>
            </div>

            <M3Dialog
                open={confirming !== null}
                onOpenChange={(open) => {
                    if (!open) setConfirming(null)
                }}
                title={t.whatsapp.disconnect}
                description={t.whatsapp.disconnectConfirm}
                actions={
                    <>
                        <DialogAction
                            label={t.common.cancel}
                            onPress={() => setConfirming(null)}
                        />
                        <DialogAction
                            label={t.whatsapp.disconnect}
                            destructive
                            onPress={() => {
                                if (confirming !== null) {
                                    void handleUnlink(confirming)
                                }
                            }}
                        />
                    </>
                }
            />
        </>
    )
}

/** The intro card each state opens with: glyph, headline, one line of copy. */
function MessageCard({
    icon,
    title,
    body,
}: {
    icon: string
    title: string
    body: string
}) {
    return (
        <GroupedCard radius={groupedRadius(0, 1)}>
            <div className="flex items-start gap-4 p-5">
                <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-primary-container text-on-primary-container">
                    <Icon name={icon} filled size={22} />
                </span>
                <div className="flex min-w-0 flex-1 flex-col">
                    <span className="m3-body-large">{title}</span>
                    <span className="m3-body-small mt-1 text-on-surface-variant">
                        {body}
                    </span>
                </div>
            </div>
        </GroupedCard>
    )
}

function StatusSkeleton() {
    return (
        <div className="flex flex-col" style={{ gap: GROUP_SPACING }}>
            <Skeleton className="h-24 rounded-[16px]" />
            <Skeleton className="h-12 w-48 rounded-full" />
        </div>
    )
}
