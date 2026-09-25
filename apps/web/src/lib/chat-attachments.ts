import { api } from '@wallet-bot/backend/api'
import {
    ATTACHMENT_IMAGE_MAX_DIMENSION,
    ATTACHMENT_MAX_BYTES,
    ATTACHMENT_TYPES,
    type AttachmentKind,
    type AttachmentType,
    JPEG_ATTACHMENT_TYPE,
    resolveAttachmentType,
} from '@wallet-bot/shared'
import type { ConvexReactClient } from 'convex/react'

/** An uploaded file the agent can read through `readAttachment`. */
export type SentAttachment = {
    id: string
    name: string
    kind: AttachmentKind
}

/** The line the model sees for an attachment (live/createToken.ts). */
export function attachmentLine(attachment: SentAttachment): string {
    return `[Attachment id=${attachment.id} name=${JSON.stringify(attachment.name)} type=${attachment.kind}]`
}

/** What a typed turn sends to the model: the text, then one line per file. */
export function composeMessageText(
    text: string,
    attachments: readonly SentAttachment[],
): string {
    return [text.trim(), ...attachments.map(attachmentLine)]
        .filter((line) => line.length > 0)
        .join('\n')
}

/** HEIC photos are converted to JPEG where the browser can decode them. */
const CONVERTIBLE_IMAGE_TYPES = new Set(['image/heic', 'image/heif'])
const CONVERTIBLE_IMAGE_EXTENSIONS = new Set(['heic', 'heif'])

/** For the file input's `accept`. */
export const ATTACHMENT_ACCEPT = [
    ...ATTACHMENT_TYPES.flatMap((type) => [
        type.mimeType,
        ...type.extensions.map((extension) => `.${extension}`),
    ]),
    ...CONVERTIBLE_IMAGE_TYPES,
    ...[...CONVERTIBLE_IMAGE_EXTENSIONS].map((extension) => `.${extension}`),
].join(',')

export type PreparedFile = {
    blob: Blob
    name: string
    type: AttachmentType
}

export type PrepareError = 'unsupported_type' | 'too_large'

function isConvertibleImage(file: File): boolean {
    const extension = file.name.split('.').pop()?.toLowerCase() ?? ''
    return (
        CONVERTIBLE_IMAGE_TYPES.has(file.type.toLowerCase()) ||
        CONVERTIBLE_IMAGE_EXTENSIONS.has(extension)
    )
}

function withExtension(name: string, extension: string): string {
    const dot = name.lastIndexOf('.')
    return `${dot > 0 ? name.slice(0, dot) : name}.${extension}`
}

/**
 * Decodes an image once and re-encodes it as JPEG no larger than
 * ATTACHMENT_IMAGE_MAX_DIMENSION on its long edge. `unchanged` when it already
 * fits and re-encoding is not forced; `null` when the browser cannot decode it.
 */
async function toJpeg(
    file: File,
    { force }: { force: boolean },
): Promise<Blob | 'unchanged' | null> {
    let bitmap: ImageBitmap
    try {
        bitmap = await createImageBitmap(file)
    } catch {
        return null
    }
    const longEdge = Math.max(bitmap.width, bitmap.height)
    if (!force && longEdge <= ATTACHMENT_IMAGE_MAX_DIMENSION) {
        bitmap.close()
        return 'unchanged'
    }
    const scale = Math.min(1, ATTACHMENT_IMAGE_MAX_DIMENSION / longEdge)
    const canvas = document.createElement('canvas')
    canvas.width = Math.round(bitmap.width * scale)
    canvas.height = Math.round(bitmap.height * scale)
    const context = canvas.getContext('2d')
    if (!context) {
        bitmap.close()
        return null
    }
    // JPEG has no alpha: transparent screenshots would otherwise turn black.
    context.fillStyle = '#ffffff'
    context.fillRect(0, 0, canvas.width, canvas.height)
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    bitmap.close()
    return new Promise((resolve) =>
        canvas.toBlob((blob) => resolve(blob), 'image/jpeg', 0.9),
    )
}

/**
 * Resolves what a picked, dropped or pasted file is and makes it uploadable:
 * HEIC becomes JPEG, oversized images are downscaled, and the size limit of
 * its kind is checked before anything is decoded.
 */
export async function prepareFile(
    file: File,
): Promise<
    { ok: true; file: PreparedFile } | { ok: false; error: PrepareError }
> {
    const convertible = isConvertibleImage(file)
    const type = convertible
        ? JPEG_ATTACHMENT_TYPE
        : resolveAttachmentType(file.type, file.name)
    if (!type) return { ok: false, error: 'unsupported_type' }
    if (file.size > ATTACHMENT_MAX_BYTES[type.kind]) {
        return { ok: false, error: 'too_large' }
    }
    if (type.kind !== 'image') {
        return { ok: true, file: { blob: file, name: file.name, type } }
    }

    const jpeg = await toJpeg(file, { force: convertible })
    if (jpeg === 'unchanged') {
        return { ok: true, file: { blob: file, name: file.name, type } }
    }
    if (jpeg === null) {
        // An image the browser cannot decode is still sent as-is when its type
        // is accepted; only HEIC depends on the conversion.
        return convertible
            ? { ok: false, error: 'unsupported_type' }
            : { ok: true, file: { blob: file, name: file.name, type } }
    }
    return {
        ok: true,
        file: {
            blob: jpeg,
            name: withExtension(file.name, 'jpg'),
            type: JPEG_ATTACHMENT_TYPE,
        },
    }
}

/** The upload endpoint enforces two minutes server-side, like feedback. */
const UPLOAD_TIMEOUT_MS = 120_000

export type UploadError =
    | 'unidentified_client'
    | 'feature_disabled'
    | 'rate_limited'
    | 'unsupported_type'
    | 'too_large'
    | 'invalid_file'
    | 'offline'
    | 'upload_failed'

/**
 * Uploads a prepared file straight to Convex storage and registers it. The
 * bytes never pass through a Convex function; the server checks the stored
 * file's own metadata on `register`.
 */
export async function uploadAttachment(
    client: ConvexReactClient,
    file: PreparedFile,
): Promise<
    { ok: true; attachment: SentAttachment } | { ok: false; error: UploadError }
> {
    if (!navigator.onLine) return { ok: false, error: 'offline' }
    const url = await client.mutation(
        api.v1.attachments.mutations.generateUploadUrl,
        {},
    )
    if (!url.ok) return { ok: false, error: url.error }

    let response: Response
    try {
        response = await fetch(url.uploadUrl, {
            method: 'POST',
            headers: { 'Content-Type': file.type.mimeType },
            body: file.blob,
            signal: AbortSignal.timeout(UPLOAD_TIMEOUT_MS),
        })
    } catch {
        return { ok: false, error: 'offline' }
    }
    if (!response.ok) return { ok: false, error: 'upload_failed' }
    const { storageId } = (await response.json()) as { storageId: string }

    const registered = await client.mutation(
        api.v1.attachments.mutations.register,
        { storageId, name: file.name },
    )
    if (!registered.ok) return { ok: false, error: registered.error }
    return {
        ok: true,
        attachment: {
            id: registered.attachmentId,
            name: file.name,
            kind: registered.kind,
        },
    }
}
