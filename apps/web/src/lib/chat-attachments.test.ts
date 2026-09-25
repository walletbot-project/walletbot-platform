// @vitest-environment jsdom

import { ATTACHMENT_MAX_BYTES } from '@wallet-bot/shared'
import { describe, expect, it } from 'vitest'
import { composeMessageText, prepareFile } from './chat-attachments'

describe('composeMessageText', () => {
    it('puts one line per attachment under the text', () => {
        expect(
            composeMessageText(' Te paso esto ', [
                { id: 'a', name: 'ticket "1".jpg', kind: 'image' },
                { id: 'b', name: 'resumen.pdf', kind: 'pdf' },
            ]),
        ).toBe(
            'Te paso esto\n[Attachment id=a name="ticket \\"1\\".jpg" type=image]\n[Attachment id=b name="resumen.pdf" type=pdf]',
        )
    })

    it('sends only the lines when there is no text', () => {
        expect(
            composeMessageText('', [{ id: 'a', name: 'x.csv', kind: 'text' }]),
        ).toBe('[Attachment id=a name="x.csv" type=text]')
    })
})

describe('prepareFile', () => {
    it('resolves a file the platform reports no type for by its extension', async () => {
        const result = await prepareFile(
            new File(['fecha,importe'], 'gastos.csv', { type: '' }),
        )
        expect(result).toMatchObject({
            ok: true,
            file: { name: 'gastos.csv', type: { mimeType: 'text/csv' } },
        })
    })

    it('rejects unsupported types and files over their kind limit', async () => {
        expect(
            await prepareFile(new File(['x'], 'app.exe', { type: '' })),
        ).toEqual({ ok: false, error: 'unsupported_type' })
        expect(
            await prepareFile(
                new File(
                    [new Uint8Array(ATTACHMENT_MAX_BYTES.text + 1)],
                    'big.txt',
                    { type: 'text/plain' },
                ),
            ),
        ).toEqual({ ok: false, error: 'too_large' })
    })

    it('refuses HEIC the browser cannot decode', async () => {
        expect(
            await prepareFile(
                new File(['x'], 'IMG_0001.HEIC', { type: 'image/heic' }),
            ),
        ).toEqual({ ok: false, error: 'unsupported_type' })
    })
})
