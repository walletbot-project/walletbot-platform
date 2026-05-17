'use node'

import type { FunctionDeclaration, Schema } from '@google/genai'
import { GoogleGenAI, Modality, Type } from '@google/genai'
import type { ToolSchema } from '@wallet-bot/shared'
import { TOOL_DEFINITIONS } from '@wallet-bot/shared'
import { action, internalAction } from '../_generated/server'

const MODEL = 'gemini-3.1-flash-live-preview'
const TOKEN_TTL_MS = 30 * 60 * 1000 // 30 minutes
const VOICE_NAME = 'Kore'

const SYSTEM_INSTRUCTION = `You are a personal finance tracking assistant. You help the user manage their expenses, income, and transfers through voice. Keep the same voice, tone, and speaking style for the entire session.`

// Shared → Google GenAI adapter

const SCHEMA_TYPE_MAP: Record<string, Type> = {
    STRING: Type.STRING,
    NUMBER: Type.NUMBER,
    INTEGER: Type.INTEGER,
    BOOLEAN: Type.BOOLEAN,
    ARRAY: Type.ARRAY,
    OBJECT: Type.OBJECT,
}

function toGoogleSchema(schema: ToolSchema): Schema {
    const result: Schema = {
        type: SCHEMA_TYPE_MAP[schema.type],
        description: schema.description,
        enum: schema.enum,
        required: schema.required,
    }
    if (schema.properties) {
        result.properties = Object.fromEntries(
            Object.entries(schema.properties).map(([k, v]) => [
                k,
                toGoogleSchema(v),
            ]),
        )
    }
    if (schema.items) {
        result.items = toGoogleSchema(schema.items)
    }
    return result
}

function toFunctionDeclarations(
    defs: readonly {
        name: string
        description: string
        parameters: ToolSchema
    }[],
): FunctionDeclaration[] {
    return defs.map((d) => ({
        name: d.name,
        description: d.description,
        parameters: toGoogleSchema(d.parameters),
    }))
}

const TOOL_DECLARATIONS = toFunctionDeclarations(TOOL_DEFINITIONS)

async function createLiveToken() {
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
                    systemInstruction: SYSTEM_INSTRUCTION,
                    tools: [{ functionDeclarations: TOOL_DECLARATIONS }],
                    speechConfig: {
                        voiceConfig: {
                            prebuiltVoiceConfig: { voiceName: VOICE_NAME },
                        },
                    },
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
}

export const requestLiveToken = action({
    args: {},
    handler: async (ctx) => {
        const identity = await ctx.auth.getUserIdentity()
        if (!identity) {
            throw new Error('Unauthenticated')
        }

        return createLiveToken()
    },
})

export const requestLiveTokenForHttp = internalAction({
    args: {},
    handler: async () => {
        return createLiveToken()
    },
})
