import { api } from '@wallet-bot/backend/api'
import { Button, CircularProgress } from 'actify'
import { useMutation } from 'convex/react'
import { type ChangeEvent, useRef, useState } from 'react'
import { toast } from 'sonner'
import { Icon } from '@/components/m3/icon'
import { useFormatLocale, useT } from '@/lib/i18n'
import type { FieldValues, UsabilitySession } from './session-data'

/** Convex upload URLs cut the POST at two minutes. */
const UPLOAD_TIMEOUT_MS = 120_000

function uploadWithProgress(
    url: string,
    file: File,
    onProgress: (percent: number) => void,
): Promise<string> {
    return new Promise((resolve, reject) => {
        const request = new XMLHttpRequest()
        request.open('POST', url)
        request.timeout = UPLOAD_TIMEOUT_MS
        request.setRequestHeader(
            'Content-Type',
            file.type || 'application/octet-stream',
        )
        request.upload.onprogress = (event) => {
            if (event.lengthComputable) {
                onProgress(Math.round((event.loaded / event.total) * 100))
            }
        }
        request.onload = () => {
            if (request.status < 200 || request.status >= 300) {
                reject(new Error(`Upload failed with ${request.status}`))
                return
            }
            try {
                const body: unknown = JSON.parse(request.responseText)
                if (
                    typeof body === 'object' &&
                    body !== null &&
                    'storageId' in body &&
                    typeof body.storageId === 'string'
                ) {
                    resolve(body.storageId)
                } else {
                    reject(new Error('Upload returned no storage id'))
                }
            } catch (error) {
                reject(error)
            }
        }
        request.onerror = () => reject(new Error('Upload failed'))
        request.ontimeout = () => reject(new Error('Upload timed out'))
        request.send(file)
    })
}

function formatSize(bytes: number, locale: string): string {
    const megabytes = bytes / (1024 * 1024)
    return `${megabytes.toLocaleString(locale, { maximumFractionDigits: 1 })} MB`
}

export function RecordingBlock({
    session,
    values,
}: {
    session: UsabilitySession
    values: FieldValues
}) {
    const t = useT()
    const locale = useFormatLocale()
    const input = useRef<HTMLInputElement>(null)
    const [uploading, setUploading] = useState(false)
    const generateUploadUrl = useMutation(
        api.v1.usability.mutations.generateRecordingUploadUrl,
    )
    const attachRecording = useMutation(
        api.v1.usability.mutations.attachRecording,
    )
    const recording = session.recording

    const upload = async (file: File) => {
        setUploading(true)
        const toastId = toast.loading(t.usability.uploading({ percent: 0 }))
        try {
            const url = await generateUploadUrl({ sessionId: session.id })
            const storageId = await uploadWithProgress(url, file, (percent) =>
                toast.loading(t.usability.uploading({ percent }), {
                    id: toastId,
                }),
            )
            await attachRecording({
                sessionId: session.id,
                storageId,
                name: file.name,
            })
            toast.success(t.usability.uploaded, { id: toastId })
        } catch {
            toast.error(t.usability.uploadFailed, { id: toastId })
        } finally {
            setUploading(false)
        }
    }

    const onPick = (event: ChangeEvent<HTMLInputElement>) => {
        const file = event.target.files?.[0]
        event.target.value = ''
        if (file) void upload(file)
    }

    return (
        <section className="flex flex-col gap-3 rounded-3xl bg-surface-container-high p-4 text-on-surface">
            <h2 className="m3-title-medium">{t.usability.recording}</h2>
            {values.get('consentimiento') === false ? (
                <p className="m3-body-medium text-on-surface-variant">
                    {t.usability.recordingNoConsent}
                </p>
            ) : null}
            {recording ? (
                <div className="flex flex-col gap-2">
                    <span className="m3-body-large break-all">
                        {recording.name}
                    </span>
                    <span className="m3-body-small text-on-surface-variant">
                        {t.usability.recordingMeta({
                            size: formatSize(recording.size, locale),
                            date: new Date(recording.uploadedAt).toLocaleString(
                                locale,
                                { dateStyle: 'medium', timeStyle: 'short' },
                            ),
                        })}
                    </span>
                    {recording.url ? (
                        <>
                            <audio
                                controls
                                preload="none"
                                src={recording.url}
                                className="w-full"
                            >
                                <track kind="captions" />
                            </audio>
                            <a
                                href={recording.url}
                                download={recording.name}
                                className="m3-label-large inline-flex items-center gap-1 text-on-surface underline"
                            >
                                <Icon name="download" size={18} />
                                {t.usability.download}
                            </a>
                        </>
                    ) : null}
                </div>
            ) : (
                <p className="m3-body-medium text-on-surface-variant">
                    {t.usability.noRecording}
                </p>
            )}
            <p className="m3-body-small text-on-surface-variant">
                {t.usability.uploadTimeoutHint}
            </p>
            <input
                ref={input}
                type="file"
                accept="audio/*,video/*"
                className="hidden"
                onChange={onPick}
            />
            <div>
                <Button
                    variant={recording ? 'outlined' : 'filled'}
                    isDisabled={uploading}
                    onPress={() => input.current?.click()}
                >
                    {uploading ? (
                        <CircularProgress
                            isIndeterminate
                            size="xs"
                            aria-label={t.usability.uploadRecording}
                        />
                    ) : (
                        <Icon name="upload" size={18} />
                    )}
                    {recording
                        ? t.usability.replaceRecording
                        : t.usability.uploadRecording}
                </Button>
            </div>
        </section>
    )
}
