'use node'

import { v } from 'convex/values'
import { z } from 'zod'
import { internalAction } from '../_generated/server'
import {
    type AttachmentReadResult,
    attachmentKindValidator,
    buildReaderRequest,
    decodeText,
    matchesSignature,
    parseReading,
    type ReaderInput,
    readContextValidator,
    readFailure,
} from './utils'

const RESPONSES_URL = 'https://api.openai.com/v1/responses'
const DEFAULT_READER_MODEL = 'gpt-6-luna'
const READER_TIMEOUT_MS = 90_000

const responseEnvelope = z.object({
    status: z.string().optional(),
    output: z.array(
        z.object({
            type: z.string(),
            content: z
                .array(
                    z.object({ type: z.string(), text: z.string().optional() }),
                )
                .optional(),
        }),
    ),
    usage: z
        .object({ input_tokens: z.number(), output_tokens: z.number() })
        .optional(),
})

/**
 * Sends one attachment and Gemini's question to the reader model (Node, for
 * `Buffer`: a 20 MB file becomes a ~27 MB base64 string). Only called by
 * `v1/attachments/actions:read` after `beginRead` passed, so the file is the
 * caller's and the read is paid for.
 *
 * `store: false` keeps the file and the answer out of OpenAI's stored
 * responses. Nothing about the content is logged here, only sizes and timing.
 */
export const readWithModel = internalAction({
    args: {
        storageId: v.id('_storage'),
        name: v.string(),
        kind: attachmentKindValidator,
        contentType: v.string(),
        question: v.string(),
        context: readContextValidator,
    },
    handler: async (ctx, args): Promise<AttachmentReadResult> => {
        const apiKey = process.env.OPEN_AI_KEY
        if (!apiKey) {
            console.error('[attachments] OPEN_AI_KEY is not set')
            return readFailure('reader_failed')
        }

        const blob = await ctx.storage.get(args.storageId)
        if (!blob) return readFailure('expired')
        const bytes = new Uint8Array(await blob.arrayBuffer())
        if (!matchesSignature(args.contentType, bytes)) {
            return readFailure('invalid_file')
        }

        let file: ReaderInput
        if (args.kind === 'text') {
            const text = decodeText(bytes)
            if (text === null) return readFailure('invalid_file')
            file = { type: 'input_text', text: `File "${args.name}":\n${text}` }
        } else {
            const dataUrl = `data:${args.contentType};base64,${Buffer.from(bytes).toString('base64')}`
            file =
                args.kind === 'image'
                    ? {
                          type: 'input_image',
                          image_url: dataUrl,
                          detail: 'high',
                      }
                    : {
                          type: 'input_file',
                          filename: args.name,
                          file_data: dataUrl,
                      }
        }

        const startedAt = Date.now()
        let response: Response
        try {
            response = await fetch(RESPONSES_URL, {
                method: 'POST',
                headers: {
                    Authorization: `Bearer ${apiKey}`,
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(
                    buildReaderRequest({
                        model:
                            process.env.OPENAI_ATTACHMENT_MODEL ??
                            DEFAULT_READER_MODEL,
                        question: args.question,
                        context: args.context,
                        file,
                        now: startedAt,
                    }),
                ),
                signal: AbortSignal.timeout(READER_TIMEOUT_MS),
            })
        } catch (error) {
            console.error('[attachments] reader request failed', {
                kind: args.kind,
                size: bytes.length,
                ms: Date.now() - startedAt,
                error: error instanceof Error ? error.name : 'unknown',
            })
            return readFailure('reader_failed')
        }

        if (!response.ok) {
            console.error('[attachments] reader rejected the request', {
                kind: args.kind,
                size: bytes.length,
                status: response.status,
                detail: (await response.text()).slice(0, 500),
            })
            return readFailure('reader_failed')
        }

        const envelope = responseEnvelope.safeParse(await response.json())
        const text = envelope.success
            ? envelope.data.output
                  .flatMap((item) => item.content ?? [])
                  .find((part) => part.type === 'output_text')?.text
            : undefined
        const reading = text === undefined ? null : parseReading(text)

        console.log('[attachments] read', {
            kind: args.kind,
            size: bytes.length,
            ms: Date.now() - startedAt,
            status: envelope.success ? envelope.data.status : 'unparsed',
            inputTokens: envelope.success
                ? envelope.data.usage?.input_tokens
                : undefined,
            outputTokens: envelope.success
                ? envelope.data.usage?.output_tokens
                : undefined,
            parsed: reading !== null,
        })

        if (!reading) return readFailure('reader_failed')
        return { ok: true, ...reading }
    },
})
