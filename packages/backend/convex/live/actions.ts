'use node'

import { GoogleGenAI, Modality } from '@google/genai'
import { action } from '../_generated/server'

const MODEL = 'gemini-3.1-flash-live-preview'
const TOKEN_TTL_MS = 30 * 60 * 1000 // 30 minutes

export const requestLiveToken = action({
    args: {},
    handler: async () => {
        const apiKey = process.env.GEMINI_API_KEY
        if (!apiKey) {
            throw new Error('GEMINI_API_KEY environment variable is not set')
        }

        const client = new GoogleGenAI({ apiKey })
        const expireTime = new Date(Date.now() + TOKEN_TTL_MS).toISOString()

        const token = await client.authTokens.create({
            config: {
                uses: 1,
                expireTime,
                liveConnectConstraints: {
                    model: MODEL,
                    config: {
                        responseModalities: [Modality.AUDIO],
                    },
                },
                httpOptions: {
                    apiVersion: 'v1alpha',
                },
            },
        })

        return {
            token: token.name,
            expireTime,
            model: MODEL,
        }
    },
})
