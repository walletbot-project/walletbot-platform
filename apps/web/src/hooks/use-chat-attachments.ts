import {
    ATTACHMENT_MAX_BYTES,
    ATTACHMENT_MAX_PER_MESSAGE,
    type AttachmentKind,
    resolveAttachmentType,
} from '@wallet-bot/shared'
import { useConvex } from 'convex/react'
import { useCallback, useEffect, useRef, useState } from 'react'
import { toast } from 'sonner'
import {
    type PrepareError,
    prepareFile,
    type SentAttachment,
    type UploadError,
    uploadAttachment,
} from '@/lib/chat-attachments'
import { type Messages, useFormatLocale, useT } from '@/lib/i18n'

export type PendingAttachment = {
    localId: string
    name: string
    kind: AttachmentKind | null
    /** Object URL of the original file, for image thumbnails. */
    previewUrl?: string
    status: 'uploading' | 'ready' | 'failed'
    attachment?: SentAttachment
}

function formatMegabytes(bytes: number, locale: string): string {
    return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(bytes / (1024 * 1024))} MB`
}

function failureMessage(
    t: Messages,
    error: PrepareError | UploadError,
    file: File,
    locale: string,
): string {
    switch (error) {
        case 'unsupported_type':
            return t.voice.attachmentUnsupported({ name: file.name })
        case 'too_large': {
            const kind = resolveAttachmentType(file.type, file.name)?.kind
            return t.voice.attachmentTooLarge({
                name: file.name,
                max: formatMegabytes(
                    ATTACHMENT_MAX_BYTES[kind ?? 'image'],
                    locale,
                ),
            })
        }
        case 'rate_limited':
            return t.voice.attachmentsRateLimited
        case 'feature_disabled':
        case 'unidentified_client':
            return t.voice.attachmentsUnavailable
        case 'offline':
            return t.voice.attachmentsOffline
        case 'invalid_file':
        case 'upload_failed':
            return t.voice.attachmentFailed({ name: file.name })
    }
}

/**
 * Files waiting in the chat composer. Each one uploads as soon as it is added
 * (one at a time, like feedback: every POST has a two-minute server deadline),
 * so by the time the user presses send only the attachment ids travel with the
 * message.
 */
export function useChatAttachments() {
    const client = useConvex()
    const t = useT()
    const formatLocale = useFormatLocale()
    const [items, setItems] = useState<PendingAttachment[]>([])
    const itemsRef = useRef(items)
    const queueRef = useRef<Promise<void>>(Promise.resolve())
    const counterRef = useRef(0)

    useEffect(() => {
        itemsRef.current = items
    }, [items])

    useEffect(
        () => () => {
            for (const item of itemsRef.current) {
                if (item.previewUrl) URL.revokeObjectURL(item.previewUrl)
            }
        },
        [],
    )

    const update = useCallback(
        (localId: string, patch: Partial<PendingAttachment>) => {
            setItems((prev) =>
                prev.map((item) =>
                    item.localId === localId ? { ...item, ...patch } : item,
                ),
            )
        },
        [],
    )

    const add = useCallback(
        (files: readonly File[]) => {
            if (files.length === 0) return
            const room = ATTACHMENT_MAX_PER_MESSAGE - itemsRef.current.length
            if (files.length > room) {
                toast.error(
                    t.voice.attachmentsTooMany({
                        max: ATTACHMENT_MAX_PER_MESSAGE,
                    }),
                )
            }
            const accepted = files.slice(0, Math.max(0, room))
            if (accepted.length === 0) return

            const batch = accepted.map((file) => {
                const kind = resolveAttachmentType(file.type, file.name)?.kind
                const item: PendingAttachment = {
                    localId: `a${++counterRef.current}`,
                    name: file.name,
                    kind: kind ?? null,
                    previewUrl: file.type.startsWith('image/')
                        ? URL.createObjectURL(file)
                        : undefined,
                    status: 'uploading',
                }
                return { file, item }
            })
            const next = [...itemsRef.current, ...batch.map((b) => b.item)]
            itemsRef.current = next
            setItems(next)

            const toastId = toast.loading(
                t.voice.attachmentsUploading({ count: batch.length }),
            )
            queueRef.current = queueRef.current.then(async () => {
                let firstFailure: string | null = null
                let succeeded = 0
                for (const { file, item } of batch) {
                    let failure: PrepareError | UploadError | null = null
                    try {
                        const prepared = await prepareFile(file)
                        if (!prepared.ok) {
                            failure = prepared.error
                        } else {
                            const uploaded = await uploadAttachment(
                                client,
                                prepared.file,
                            )
                            if (uploaded.ok) {
                                succeeded += 1
                                update(item.localId, {
                                    status: 'ready',
                                    name: uploaded.attachment.name,
                                    kind: uploaded.attachment.kind,
                                    attachment: uploaded.attachment,
                                })
                                continue
                            }
                            failure = uploaded.error
                        }
                    } catch (error) {
                        console.error('attaching a file failed', error)
                        failure = 'upload_failed'
                    }
                    update(item.localId, { status: 'failed' })
                    firstFailure ??= failureMessage(
                        t,
                        failure,
                        file,
                        formatLocale,
                    )
                }
                if (firstFailure) {
                    toast.error(firstFailure, { id: toastId })
                } else {
                    toast.success(
                        t.voice.attachmentsReady({ count: succeeded }),
                        { id: toastId },
                    )
                }
            })
        },
        [client, formatLocale, t, update],
    )

    const remove = useCallback((localId: string) => {
        const item = itemsRef.current.find((i) => i.localId === localId)
        if (item?.previewUrl) URL.revokeObjectURL(item.previewUrl)
        const next = itemsRef.current.filter((i) => i.localId !== localId)
        itemsRef.current = next
        setItems(next)
    }, [])

    /**
     * Hands the uploaded attachments to the message being sent and empties the
     * composer. Failed ones are dropped with them; they already said so.
     */
    const take = useCallback((): SentAttachment[] => {
        const sent = itemsRef.current.flatMap((item) =>
            item.status === 'ready' && item.attachment ? [item.attachment] : [],
        )
        for (const item of itemsRef.current) {
            if (item.previewUrl) URL.revokeObjectURL(item.previewUrl)
        }
        itemsRef.current = []
        setItems([])
        return sent
    }, [])

    return {
        items,
        add,
        remove,
        take,
        isUploading: items.some((item) => item.status === 'uploading'),
        hasReady: items.some((item) => item.status === 'ready'),
    }
}
