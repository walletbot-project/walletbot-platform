import { api } from '@wallet-bot/backend/api'
import {
    FEEDBACK_MAX_FILE_BYTES,
    FEEDBACK_MAX_FILE_MB,
    FEEDBACK_MAX_FILES,
    FEEDBACK_MAX_TEXT_CHARS,
    isSubmittableFeedback,
} from '@wallet-bot/shared'
import { Button, IconButton, TextField } from 'actify'
import { useMutation } from 'convex/react'
import { useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { BottomSheet } from '@/components/m3/bottom-sheet'
import { Icon } from '@/components/m3/icon'
import {
    resolveWebDeviceId,
    WEB_APP_VERSION,
    WEB_PLATFORM,
} from '@/lib/client-info'
import { type Messages, useFormatLocale, useT } from '@/lib/i18n'

/**
 * The feedback form, presented as an adaptive sheet over the home screen.
 *
 * It is a **route** (`/feedback`, a child of `/`), not a `useState` modal:
 * this is a form the user types into and attaches files to, and component
 * state would be at the mercy of anything that remounts the page — crossing
 * the 600px breakpoint remounts the whole routed page (LESSONS.md #13/#14), so
 * a resize would silently discard a half-written report. The URL owning it also
 * buys reload, back/forward and a deep link for free.
 */
export function FeedbackRoute() {
    const t = useT()
    const locale = useFormatLocale()
    const navigate = useNavigate()

    const generateUploadUrl = useMutation(
        api.v1.feedback.mutations.generateUploadUrl,
    )
    const submit = useMutation(api.v1.feedback.mutations.submit)

    const [text, setText] = useState('')
    const [files, setFiles] = useState<File[]>([])
    const [sending, setSending] = useState(false)
    const fileInput = useRef<HTMLInputElement>(null)

    const close = () => {
        // Back rather than a push to '/', so the sheet leaves the history stack
        // it entered instead of stacking another entry on it.
        navigate(-1)
    }

    const addFiles = (picked: FileList | null) => {
        if (!picked) return
        const incoming = Array.from(picked)

        const tooBig = incoming.find(
            (file) => file.size > FEEDBACK_MAX_FILE_BYTES,
        )
        if (tooBig) {
            toast.error(
                t.feedback.fileTooLarge({
                    name: tooBig.name,
                    mb: FEEDBACK_MAX_FILE_MB,
                }),
            )
            return
        }
        if (files.length + incoming.length > FEEDBACK_MAX_FILES) {
            toast.error(t.feedback.tooManyFiles({ max: FEEDBACK_MAX_FILES }))
            return
        }

        setFiles((current) => [...current, ...incoming])
        // Clear the input so re-picking the same file fires `change` again.
        if (fileInput.current) fileInput.current.value = ''
    }

    const removeFile = (index: number) => {
        setFiles((current) => current.filter((_, at) => at !== index))
    }

    /**
     * Uploads every attachment, then records the report.
     *
     * Files are uploaded here rather than when they are picked, so abandoning
     * the form costs nothing: a sheet the user closes leaves no bytes behind.
     * The trade is that a failure partway through a batch does orphan the files
     * already uploaded — nothing references them, and the rate limits bound how
     * many a caller can create.
     */
    const send = async () => {
        const trimmed = text.trim()
        if (
            !isSubmittableFeedback({
                text: trimmed,
                attachmentCount: files.length,
            })
        ) {
            toast.error(t.feedback.empty)
            return
        }
        if (trimmed.length > FEEDBACK_MAX_TEXT_CHARS) {
            toast.error(
                t.feedback.textTooLong({ max: FEEDBACK_MAX_TEXT_CHARS }),
            )
            return
        }

        setSending(true)
        const deviceId = resolveWebDeviceId()
        // One toast carried from loading to its verdict. `toast.promise` does
        // not fit here: a submission is a chain of uploads followed by the
        // record, and several of its outcomes are resolved `{ ok: false }`
        // results rather than rejections, which a promise toast would show as
        // success.
        const toastId = toast.loading(t.feedback.sending)
        const fail = (message: string) => toast.error(message, { id: toastId })
        try {
            const attachments: {
                storageId: string
                filename: string | null
            }[] = []

            for (const file of files) {
                const minted = await generateUploadUrl({ deviceId })
                if (!minted.ok) {
                    fail(t.feedback.rateLimited)
                    return
                }
                const response = await fetch(minted.uploadUrl, {
                    method: 'POST',
                    headers: file.type ? { 'Content-Type': file.type } : {},
                    body: file,
                })
                if (!response.ok) {
                    fail(t.feedback.uploadFailed({ name: file.name }))
                    return
                }
                const { storageId } = (await response.json()) as {
                    storageId: string
                }
                attachments.push({ storageId, filename: file.name })
            }

            const result = await submit({
                text: trimmed,
                attachments,
                platform: WEB_PLATFORM,
                appVersion: WEB_APP_VERSION,
                deviceId,
                locale,
            })

            if (!result.ok) {
                fail(rejectionMessage(result.error, t))
                return
            }

            toast.success(t.feedback.sent, { id: toastId })
            close()
        } catch {
            fail(t.feedback.sendFailed)
        } finally {
            setSending(false)
        }
    }

    return (
        <BottomSheet
            // Mounted only while the route matches; while rendered it is open.
            open
            onOpenChange={(open) => {
                if (!open) close()
            }}
            title={t.feedback.title}
            showTitle
            footer={
                <Button
                    variant="filled"
                    className="w-full"
                    isDisabled={sending}
                    onPress={() => void send()}
                >
                    {sending ? t.feedback.sending : t.feedback.submit}
                </Button>
            }
        >
            <div className="flex flex-col gap-5 px-4 pb-6">
                <p className="m3-body-medium text-on-surface-variant">
                    {t.feedback.intro}
                </p>

                <TextField
                    variant="outlined"
                    type="textarea"
                    className="min-h-32 w-full"
                    label={t.feedback.messageLabel}
                    placeholder={t.feedback.messagePlaceholder}
                    value={text}
                    onChange={setText}
                    maxLength={FEEDBACK_MAX_TEXT_CHARS}
                />

                <div className="flex flex-col gap-3">
                    <div className="flex items-center justify-between gap-3">
                        <span className="m3-title-small">
                            {t.feedback.attachments}
                        </span>
                        <Button
                            variant="outlined"
                            isDisabled={
                                sending || files.length >= FEEDBACK_MAX_FILES
                            }
                            onPress={() => fileInput.current?.click()}
                        >
                            <Icon name="attach_file" size={18} />
                            {t.feedback.addFiles}
                        </Button>
                    </div>

                    <span className="m3-body-small text-on-surface-variant">
                        {t.feedback.attachmentsHint({
                            max: FEEDBACK_MAX_FILES,
                            mb: FEEDBACK_MAX_FILE_MB,
                        })}
                    </span>

                    {/*
                     * Any file type, matching native's `FileType.any`: a
                     * screenshot, a screen recording, or an exported log are
                     * all legitimate evidence for a bug report.
                     */}
                    <input
                        ref={fileInput}
                        type="file"
                        multiple
                        className="hidden"
                        onChange={(event) => addFiles(event.target.files)}
                    />

                    {files.length > 0 ? (
                        <ul className="flex flex-col gap-2">
                            {files.map((file, index) => (
                                <li
                                    key={`${file.name}-${file.lastModified}-${file.size}`}
                                    className="flex items-center gap-3 rounded-xl bg-surface-container-high px-3 py-2"
                                >
                                    <Icon
                                        name={fileIcon(file.type)}
                                        className="text-on-surface-variant"
                                        size={20}
                                    />
                                    <span className="m3-body-medium min-w-0 flex-1 truncate">
                                        {file.name}
                                    </span>
                                    <span className="m3-body-small shrink-0 text-on-surface-variant">
                                        {formatBytes(file.size, locale)}
                                    </span>
                                    <IconButton
                                        aria-label={t.feedback.removeFile({
                                            name: file.name,
                                        })}
                                        isDisabled={sending}
                                        onPress={() => removeFile(index)}
                                        className="text-on-surface-variant"
                                    >
                                        <Icon name="close" size={18} />
                                    </IconButton>
                                </li>
                            ))}
                        </ul>
                    ) : null}
                </div>
            </div>
        </BottomSheet>
    )
}

/** Maps a `submit` refusal onto the localized copy for it. */
function rejectionMessage(
    error:
        | 'rate_limited'
        | 'empty'
        | 'text_too_long'
        | 'too_many_files'
        | 'file_too_large'
        | 'unknown_attachment',
    t: Messages,
): string {
    switch (error) {
        case 'rate_limited':
            return t.feedback.rateLimited
        case 'empty':
            return t.feedback.empty
        case 'text_too_long':
            return t.feedback.textTooLong({ max: FEEDBACK_MAX_TEXT_CHARS })
        case 'too_many_files':
            return t.feedback.tooManyFiles({ max: FEEDBACK_MAX_FILES })
        case 'file_too_large':
            // The server checks stored sizes, so it cannot name which file
            // failed — the client-side check above is what names one.
            return t.feedback.fileTooLargeGeneric({ mb: FEEDBACK_MAX_FILE_MB })
        case 'unknown_attachment':
            return t.feedback.unknownAttachment
    }
}

/** Material Symbols ligature standing in for a file's kind. */
function fileIcon(contentType: string): string {
    if (contentType.startsWith('image/')) return 'image'
    if (contentType.startsWith('video/')) return 'movie'
    if (contentType.startsWith('audio/')) return 'graphic_eq'
    return 'description'
}

function formatBytes(bytes: number, locale: string): string {
    const mb = bytes / (1024 * 1024)
    if (mb >= 1) {
        return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(mb)} MB`
    }
    const kb = Math.max(1, Math.round(bytes / 1024))
    return `${new Intl.NumberFormat(locale).format(kb)} KB`
}
