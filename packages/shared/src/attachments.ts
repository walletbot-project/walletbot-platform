/**
 * Files a user attaches to the agent chat. Clients pre-check these for UX; the
 * server enforces them against the `_storage` metadata of the uploaded file
 * (`v1/attachments/mutations.ts`), which is the only trustworthy size.
 */

export type AttachmentKind =
    | 'image'
    | 'pdf'
    | 'document'
    | 'spreadsheet'
    | 'text'

export const ATTACHMENT_MAX_PER_MESSAGE = 5

/** Longest image edge clients send; larger images are downscaled first. */
export const ATTACHMENT_IMAGE_MAX_DIMENSION = 2048

export const ATTACHMENT_MAX_NAME_LENGTH = 256

export const ATTACHMENT_MAX_QUESTION_LENGTH = 1000

/** How long an attachment stays readable by the agent after upload. */
export const ATTACHMENT_TTL_MS = 24 * 60 * 60 * 1000

const MB = 1024 * 1024

export const ATTACHMENT_MAX_BYTES: Readonly<Record<AttachmentKind, number>> = {
    image: 20 * MB,
    pdf: 20 * MB,
    document: 20 * MB,
    spreadsheet: 2 * MB,
    text: 2 * MB,
}

export type AttachmentType = {
    mimeType: string
    kind: AttachmentKind
    extensions: readonly string[]
}

/**
 * Every accepted type. Clients upload with exactly one of these `mimeType`s
 * (resolved from the file's own type, or from its extension when the platform
 * reports none), so the server only has to match the stored content type.
 */
/** What clients re-encode HEIC photos and oversized images into. */
export const JPEG_ATTACHMENT_TYPE: AttachmentType = {
    mimeType: 'image/jpeg',
    kind: 'image',
    extensions: ['jpg', 'jpeg'],
}

export const ATTACHMENT_TYPES: readonly AttachmentType[] = [
    JPEG_ATTACHMENT_TYPE,
    { mimeType: 'image/png', kind: 'image', extensions: ['png'] },
    { mimeType: 'image/webp', kind: 'image', extensions: ['webp'] },
    { mimeType: 'image/gif', kind: 'image', extensions: ['gif'] },
    { mimeType: 'application/pdf', kind: 'pdf', extensions: ['pdf'] },
    {
        mimeType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        kind: 'document',
        extensions: ['docx'],
    },
    {
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        kind: 'spreadsheet',
        extensions: ['xlsx'],
    },
    { mimeType: 'text/plain', kind: 'text', extensions: ['txt', 'log'] },
    { mimeType: 'text/csv', kind: 'text', extensions: ['csv'] },
    {
        mimeType: 'text/tab-separated-values',
        kind: 'text',
        extensions: ['tsv'],
    },
    { mimeType: 'text/markdown', kind: 'text', extensions: ['md', 'markdown'] },
    { mimeType: 'application/json', kind: 'text', extensions: ['json'] },
    { mimeType: 'application/x-ofx', kind: 'text', extensions: ['ofx', 'qfx'] },
    { mimeType: 'application/qif', kind: 'text', extensions: ['qif'] },
]

const GENERIC_MIME_TYPES = new Set(['', 'application/octet-stream'])

export function attachmentTypeForMime(
    mimeType: string | undefined,
): AttachmentType | undefined {
    const normalized = (mimeType ?? '').split(';')[0].trim().toLowerCase()
    return ATTACHMENT_TYPES.find((type) => type.mimeType === normalized)
}

/**
 * Resolves what a picked, dropped or pasted file is. The reported type wins;
 * the extension decides only when the platform reports nothing useful, which
 * is common for csv, md, ofx and qif.
 */
export function resolveAttachmentType(
    mimeType: string | undefined,
    fileName: string,
): AttachmentType | undefined {
    const normalized = (mimeType ?? '').split(';')[0].trim().toLowerCase()
    if (!GENERIC_MIME_TYPES.has(normalized)) {
        const byMime = attachmentTypeForMime(normalized)
        if (byMime) return byMime
    }
    const extension = fileName.split('.').pop()?.toLowerCase() ?? ''
    return ATTACHMENT_TYPES.find((type) => type.extensions.includes(extension))
}
