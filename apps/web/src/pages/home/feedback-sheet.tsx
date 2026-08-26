import { api } from '@wallet-bot/backend/api'
import {
    FEEDBACK_MAX_ATTACHMENT_BYTES,
    FEEDBACK_MAX_ATTACHMENTS,
    FEEDBACK_MAX_MESSAGE_LENGTH,
} from '@wallet-bot/shared'
import { Button, IconButton, TextField } from 'actify'
import { useMutation } from 'convex/react'
import { useRef, useState } from 'react'
import { toast } from 'sonner'
import { BottomSheet } from '@/components/m3/bottom-sheet'
import { Icon } from '@/components/m3/icon'
import { useFormatLocale, useI18n, useT } from '@/lib/i18n'
import { SupportEmailDialog } from './support-email-dialog'

type FeedbackSheetProps = {
    open: boolean
    onOpenChange: (open: boolean) => void
}

/**
 * How long a single attachment upload may run. The upload endpoint enforces two
 * minutes server-side, so the client gives up when the server would.
 *
 * The Convex mutations get no deadline: the client owns their delivery and
 * retries them across a reconnect, so cutting one short would claim a failure
 * for a submission still on its way, and a retry would file it twice.
 */
const UPLOAD_TIMEOUT_MS = 120_000

/**
 * The home screen's "Send feedback" surface: a message plus up to
 * `FEEDBACK_MAX_ATTACHMENTS` files of `FEEDBACK_MAX_ATTACHMENT_BYTES` each.
 *
 * Files never pass through a Convex function. For each one the sheet asks
 * `generateAttachmentUploadUrl` for a short-lived URL, POSTs the bytes straight
 * to it, and finally sends only the resulting storage ids to `submit`. The
 * uploads run one at a time on purpose: every POST has a hard two-minute
 * server-side timeout, which ten parallel 100 MB uploads sharing one connection
 * would blow through.
 */
export function FeedbackSheet({ open, onOpenChange }: FeedbackSheetProps) {
    const t = useT()
    const { locale } = useI18n()
    const formatLocale = useFormatLocale()
    const fileInput = useRef<HTMLInputElement>(null)

    const [message, setMessage] = useState('')
    const [files, setFiles] = useState<File[]>([])
    const [sending, setSending] = useState(false)
    /**
     * The last failure, shown inside the sheet. A toast alone puts the reason
     * outside the surface the user is looking at, and on the narrow layout the
     * sheet covers where it appears.
     */
    const [error, setError] = useState<string | null>(null)
    const [emailOpen, setEmailOpen] = useState(false)

    const generateUploadUrl = useMutation(
        api.v1.feedback.mutations.generateAttachmentUploadUrl,
    )
    const submitFeedback = useMutation(api.v1.feedback.mutations.submit)

    const maxSize = formatFileSize(FEEDBACK_MAX_ATTACHMENT_BYTES, formatLocale)

    const addFiles = (picked: FileList | null) => {
        if (!picked || picked.length === 0) return
        const accepted: File[] = []
        let rejection: string | null = null
        for (const file of picked) {
            if (file.size > FEEDBACK_MAX_ATTACHMENT_BYTES) {
                rejection ??= t.feedback.fileTooLarge({
                    name: file.name,
                    max: maxSize,
                })
                continue
            }
            if (files.length + accepted.length >= FEEDBACK_MAX_ATTACHMENTS) {
                rejection ??= t.feedback.tooManyFiles({
                    max: FEEDBACK_MAX_ATTACHMENTS,
                })
                break
            }
            accepted.push(file)
        }
        setError(rejection)
        if (accepted.length > 0) setFiles([...files, ...accepted])
    }

    const removeFile = (index: number) =>
        setFiles(files.filter((_, position) => position !== index))

    const close = () => {
        setMessage('')
        setFiles([])
        setError(null)
        onOpenChange(false)
    }

    const send = async () => {
        const trimmed = message.trim()
        if (!trimmed) {
            setError(t.feedback.messageRequired)
            return
        }
        // Cheap and certain: the browser already knows there is no network, so
        // there is no reason to spend the timeout finding out.
        if (!navigator.onLine) {
            setError(t.feedback.offline)
            return
        }

        setSending(true)
        setError(null)
        const toastId = toast.loading(t.feedback.sending)
        try {
            const attachments: { storageId: string; name: string }[] = []
            for (const [index, file] of files.entries()) {
                toast.loading(
                    t.feedback.uploading({
                        current: index + 1,
                        total: files.length,
                    }),
                    { id: toastId },
                )
                const urlResult = await generateUploadUrl({})
                if (!urlResult.ok) {
                    throw new FeedbackError(urlResult.error)
                }
                let response: Response
                try {
                    response = await fetch(urlResult.uploadUrl, {
                        method: 'POST',
                        headers: file.type
                            ? { 'Content-Type': file.type }
                            : undefined,
                        body: file,
                        signal: AbortSignal.timeout(UPLOAD_TIMEOUT_MS),
                    })
                } catch (caught) {
                    // `fetch` rejects with a TypeError when the request never
                    // got out and with a TimeoutError once it runs past the
                    // deadline above. Both are the connection. Caught here
                    // rather than sorted out at the end, so a TypeError from
                    // this component's own code never reads as "no connection".
                    throw new OfflineError('upload never got out', {
                        cause: caught,
                    })
                }
                if (!response.ok) throw new Error('upload failed')
                const { storageId } = (await response.json()) as {
                    storageId: string
                }
                attachments.push({ storageId, name: file.name })
            }

            toast.loading(t.feedback.sending, { id: toastId })
            const result = await submitFeedback({
                message: trimmed,
                attachments,
                platform: 'web',
                locale,
            })
            if (!result.ok) throw new FeedbackError(result.error)

            toast.success(t.feedback.sent, { id: toastId })
            close()
        } catch (caught) {
            // The sheet stays open with the text and the picked files intact, so
            // a rate limit or a dropped upload never costs the user what they
            // wrote. The reason goes in the sheet, not in the toast: the toast
            // is gone in seconds and the retry button is here.
            console.error('sending feedback failed', caught)
            toast.dismiss(toastId)
            setError(errorMessage(caught, t))
        } finally {
            setSending(false)
        }
    }

    return (
        <>
            <BottomSheet
                open={open}
                onOpenChange={(next) => {
                    if (!next && !sending) close()
                }}
                title={t.feedback.title}
                showTitle
                footer={
                    <div className="flex gap-3">
                        <Button
                            variant="outlined"
                            className="flex-1"
                            isDisabled={sending}
                            onPress={close}
                        >
                            {t.common.cancel}
                        </Button>
                        <Button
                            variant="filled"
                            className="flex-1"
                            isDisabled={sending || message.trim().length === 0}
                            onPress={() => void send()}
                        >
                            {t.feedback.send}
                        </Button>
                    </div>
                }
            >
                <div className="flex flex-col gap-5 px-4 pb-6">
                    <p className="m3-body-medium text-on-surface-variant">
                        {t.feedback.subtitle}
                    </p>

                    {/*
                     * `className` reaches the textarea element itself (actify
                     * spreads it there), which is how the field gets its height
                     * — the component takes no `rows`.
                     */}
                    <TextField
                        variant="outlined"
                        className="min-h-28 w-full"
                        type="textarea"
                        label={t.feedback.messageLabel}
                        placeholder={t.feedback.messagePlaceholder}
                        value={message}
                        onChange={setMessage}
                        maxLength={FEEDBACK_MAX_MESSAGE_LENGTH}
                        isDisabled={sending}
                        isRequired
                    />

                    <div className="flex flex-col gap-2">
                        <Button
                            variant="outlined"
                            className="self-start"
                            isDisabled={
                                sending ||
                                files.length >= FEEDBACK_MAX_ATTACHMENTS
                            }
                            onPress={() => fileInput.current?.click()}
                        >
                            <Icon name="attach_file" size={18} />
                            {t.feedback.attach}
                        </Button>
                        <input
                            ref={fileInput}
                            type="file"
                            multiple
                            hidden
                            onChange={(event) => {
                                addFiles(event.target.files)
                                // Clear it so re-picking the same file fires again.
                                event.target.value = ''
                            }}
                        />
                        <span className="m3-body-small text-on-surface-variant">
                            {t.feedback.attachmentsCount({
                                count: files.length,
                                max: FEEDBACK_MAX_ATTACHMENTS,
                                maxSize,
                            })}
                        </span>
                    </div>

                    {files.length > 0 ? (
                        <ul className="flex flex-col gap-2">
                            {files.map((file, index) => (
                                <li
                                    key={`${file.name}-${file.lastModified}-${file.size}`}
                                    className="flex items-center gap-3 rounded-xl bg-surface-container-high px-3 py-2"
                                >
                                    <Icon
                                        name="description"
                                        className="text-on-surface-variant"
                                    />
                                    <div className="flex min-w-0 flex-1 flex-col">
                                        <span className="m3-body-medium truncate">
                                            {file.name}
                                        </span>
                                        <span className="m3-body-small text-on-surface-variant">
                                            {formatFileSize(
                                                file.size,
                                                formatLocale,
                                            )}
                                        </span>
                                    </div>
                                    <IconButton
                                        aria-label={t.feedback.removeAttachment}
                                        isDisabled={sending}
                                        onPress={() => removeFile(index)}
                                        className="text-on-surface-variant"
                                    >
                                        <Icon name="close" />
                                    </IconButton>
                                </li>
                            ))}
                        </ul>
                    ) : null}

                    {error ? (
                        <div
                            role="alert"
                            className="flex items-start gap-2 rounded-xl bg-error-container px-3 py-2 text-on-error-container"
                        >
                            <Icon name="error" size={20} className="mt-0.5" />
                            <p className="m3-body-medium flex-1">{error}</p>
                            <IconButton
                                aria-label={t.feedback.errorDismiss}
                                onPress={() => setError(null)}
                                className="text-on-error-container"
                            >
                                <Icon name="close" size={18} />
                            </IconButton>
                        </div>
                    ) : null}

                    <Button
                        variant="text"
                        className="self-start"
                        isDisabled={sending}
                        onPress={() => setEmailOpen(true)}
                    >
                        <Icon name="mail" size={18} />
                        {t.feedback.emailInstead}
                    </Button>
                </div>
            </BottomSheet>

            <SupportEmailDialog
                open={emailOpen}
                onOpenChange={setEmailOpen}
                draft={message.trim()}
            />
        </>
    )
}

/** A rejection the server explained, so the sheet can show its own copy. */
class FeedbackError extends Error {
    reason: string

    constructor(reason: string) {
        super(reason)
        this.reason = reason
    }
}

/** The request never reached the server, so the answer is about the connection. */
class OfflineError extends Error {}

function errorMessage(error: unknown, t: ReturnType<typeof useT>): string {
    if (error instanceof FeedbackError) {
        if (error.reason === 'rate_limited') return t.feedback.rateLimited
        if (error.reason === 'attachment_invalid') {
            return t.feedback.attachmentRejected
        }
        if (error.reason === 'message_invalid') {
            return t.feedback.messageRequired
        }
        return t.feedback.sendFailed
    }
    if (error instanceof OfflineError) return t.feedback.offline
    return t.feedback.sendFailed
}

/**
 * Locale-aware file size, so the unit is never a hardcoded string. Megabytes
 * above 1 MB, kilobytes below.
 */
function formatFileSize(bytes: number, locale: string): string {
    const megabytes = bytes / (1024 * 1024)
    return megabytes >= 1
        ? new Intl.NumberFormat(locale, {
              style: 'unit',
              unit: 'megabyte',
              maximumFractionDigits: 1,
          }).format(megabytes)
        : new Intl.NumberFormat(locale, {
              style: 'unit',
              unit: 'kilobyte',
              maximumFractionDigits: 0,
          }).format(Math.max(1, bytes / 1024))
}
