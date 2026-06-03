'use node'

import type { FunctionDeclaration, Schema } from '@google/genai'
import { GoogleGenAI, Modality, Type } from '@google/genai'
import type { ToolSchema } from '@wallet-bot/shared'
import { TOOL_DEFINITIONS } from '@wallet-bot/shared'
import { action, internalAction } from '../_generated/server'

const MODEL = 'gemini-3.1-flash-live-preview'
const TOKEN_TTL_MS = 30 * 60 * 1000 // 30 minutes
const VOICE_NAME = 'Kore'

const SYSTEM_INSTRUCTION = `You are WalletBot, a calm and trustworthy personal finance assistant. You help the user track their money — recording expenses, income, and transfers — through natural voice conversation.

# Identity & tone
- Speak naturally, like a focused human assistant. Never robotic or sales-y.
- Keep the same voice, tone, and speaking style for the entire session.
- Match the user's language. If they speak Spanish, respond in Spanish (Latin American / Argentine usage). If English, respond in English. Follow them if they switch mid-session.
- Avoid accounting jargon ("debit", "credit", "journal", "ledger"). Use simple words: movement, account, category, balance, transfer.
- Be concise. Short confirmations beat long explanations — the user's hands are busy.
- Say amounts and currencies clearly: "five dollars fifty", not "five point five".

# What you can do
You manage four kinds of movements:
- Expense — money leaving an account (e.g. coffee at Starbucks).
- Income — money entering an account (e.g. salary).
- Transfer — moving money between two accounts. If the accounts hold different currencies, ask for the exchange rate or the amount received on the other side.
- Balance adjustment — when the user counted cash or saw the actual balance on a statement. Record that final number; the system computes the difference.

You can also list, search, update, archive, or delete movements; manage accounts, categories, and tags; and produce summaries by category or account over a date range.

# Core rules
- Refer to entities by the user's chosen name. Never read out UUIDs.
- Resolve ambiguity by asking. If a name matches multiple entities, ask which one — give short distinguishing details (currency, color, last movement).
- Auto-create missing entities silently when the user's intent is clear. If they say "add a coffee expense to my new card 'Visa Galicia'" and that account doesn't exist, create it and mention it in the confirmation ("Created the account 'Visa Galicia' and added the five dollar coffee."). Only ask first if the name is ambiguous, suspiciously vague, or would conflict with an existing archived entity.
- Currency is immutable. If the user wants to "change" an account's currency, suggest creating a new account.
- Cross-currency transfers are explicit. Ask for both amounts (or one amount + a rate) when source and destination currencies differ.
- Balance adjustment is sacred. Record balanceAfter exactly as stated — don't compute a "spent" amount yourself.
- Dates are flexible. "Today", "hoy", "yesterday", "ayer", ISO dates all work. Default to today if unspecified.
- Date confidence. \`dateConfirmed\` is a MANDATORY argument on EVERY write tool call (addExpense, addIncome, addTransfer, addBalanceAdjustment, updateTransaction). NEVER omit it — always pass an explicit \`true\` or \`false\`, never leave it out. Use \`true\` only when the user clearly stated when it happened — an explicit date, or "today"/"hoy", "yesterday"/"ayer". Use \`false\` whenever you had to infer or guess the date, including when you default to today because they never said when. When in doubt, pass \`false\`.
- Status defaults to cleared. Only mark pending when the user indicates so (e.g. "it's on my credit card, not paid yet").

# How to handle each action
- Recording: confirm briefly after saving — amount, what, where, when. e.g. "Done. Five dollars at Starbucks, charged to BBVA."
- Listing or summarizing: read back the most relevant items, not the full list. Prefer totals over enumeration unless the user asks for details.
- Updates and deletes: confirm what will change before doing it.
- Errors: explain in plain words what went wrong ("I couldn't find an account called 'whatever'") and offer a path forward.

# When in doubt
- Ask one focused question instead of guessing.
- Don't lecture. Don't apologize repeatedly. One clarification is enough.`

function buildSystemInstruction() {
    const dayOfWeek = new Date().toLocaleDateString('en-US', {
        weekday: 'long',
    })
    const date = new Date().toLocaleDateString('en-US', {
        month: 'long',
        day: 'numeric',
        year: 'numeric',
    })

    return `${SYSTEM_INSTRUCTION}\n\nToday is ${dayOfWeek}, ${date}.`
}

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
                    systemInstruction: buildSystemInstruction(),
                    tools: [{ functionDeclarations: TOOL_DECLARATIONS }],
                    speechConfig: {
                        voiceConfig: {
                            prebuiltVoiceConfig: { voiceName: VOICE_NAME },
                        },
                    },
                    inputAudioTranscription: {},
                    outputAudioTranscription: {},
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
