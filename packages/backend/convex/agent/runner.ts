'use node'

// The text-channel agent: a Gemini tool-calling loop that runs entirely on the
// server.
//
// The voice agent (`live/createToken.ts`) hands the device a short-lived token
// and the phone talks to Gemini directly, executing tools against its own
// database. Nothing about that shape transfers here — a WhatsApp message
// arrives with no device attached, so the model call, the tool execution and
// the reply all happen inside one Convex action.
//
// `'use node'` for `@google/genai`. Everything it imports is either pure or
// itself a Node module, per the import-chain rule in CLAUDE.md.

import type {
    Content,
    FunctionCall,
    FunctionDeclaration,
    GenerateContentResponse,
    Part,
} from '@google/genai'
import { GoogleGenAI, ThinkingLevel } from '@google/genai'
import { TOOL_MAP } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { internal } from '../_generated/api'
import type { ActionCtx } from '../_generated/server'
import { internalAction } from '../_generated/server'
import type { FlagKey } from '../featureFlags/utils'
import { writeKeyFor } from './idempotency'
import { buildTextSystemInstruction } from './prompt'
import { toFunctionDeclarations } from './schema'
import { AGENT_TOOL_NAMES, flagForTool } from './toolset'

// Overridable so a model can be rolled forward without a code change, which
// matters when a preview model is retired at Google's pace rather than ours.
const DEFAULT_MODEL = 'gemini-3-flash-preview'

// How many times the model may call tools before we stop and answer with what
// we have. Recording an expense takes one or two rounds; a summary that has to
// resolve names first takes three or four. Well past that the model is
// looping, and a WhatsApp user is watching two grey ticks the whole time.
const MAX_TOOL_ROUNDS = 8

// Guardrail on a single turn's tool calls, independent of rounds: the model can
// emit several calls per round.
const MAX_TOOL_CALLS = 24

// Declared per turn rather than once at module load: a flag-gated tool is only
// offered to users the rollout has reached. Same gate the voice channel applies
// when it mints a token (`live/createToken.ts`), and `agent/tools.ts` re-checks
// it on execution rather than trusting this list.
const declarationsFor = (
    flags: Partial<Record<FlagKey, boolean>>,
): FunctionDeclaration[] =>
    toFunctionDeclarations(
        AGENT_TOOL_NAMES.filter((name) => {
            const flag = flagForTool(name)
            return flag === undefined || flags[flag] === true
        }).map((name) => TOOL_MAP[name]),
    )

export type AgentMessage = {
    role: 'user' | 'model'
    text: string
}

export type AgentResult = {
    text: string
    toolCalls: number
    rounds: number
}

// What the user gets when the model produced nothing usable. Silence would be
// worse: on WhatsApp an unanswered message is indistinguishable from a broken
// bot.
const FALLBACK_REPLY: Record<'es' | 'en', string> = {
    es: 'Perdón, no pude procesar eso. ¿Lo intentás de nuevo?',
    en: "Sorry, I couldn't process that. Could you try again?",
}

// Shown when Gemini itself is unavailable — most often the per-minute request
// quota, which the free tier exhausts in three turns. Distinct from the
// fallback above because the user should retry in a moment, not rephrase.
const BUSY_REPLY: Record<'es' | 'en', string> = {
    es: 'Estoy saturado en este momento. Probá de nuevo en un minuto.',
    en: "I'm overloaded right now. Try again in a minute.",
}

// Recoverable upstream conditions: rate limits, overload, and transient
// server errors. Anything else is a bug in our request and should surface.
const isTransientModelError = (error: unknown): boolean => {
    const message = error instanceof Error ? error.message : String(error)
    return /\b(429|RESOURCE_EXHAUSTED|503|UNAVAILABLE|500|INTERNAL|deadline)\b/i.test(
        message,
    )
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
    typeof value === 'object' && value !== null && !Array.isArray(value)

// Gemini's `args` are loosely typed JSON. They are handed to the executor as a
// string and validated there against the shared zod schemas, so nothing
// untyped crosses into the database layer.
const argsToJson = (args: FunctionCall['args']): string =>
    JSON.stringify(isRecord(args) ? args : {})

const parseToolResult = (json: string): Record<string, unknown> => {
    const parsed: unknown = JSON.parse(json)
    return isRecord(parsed) ? parsed : { ok: false, error: 'malformed result' }
}

export const runAgent = async (
    ctx: ActionCtx,
    args: {
        userId: string
        messages: AgentMessage[]
        nowMs: number
        utcOffsetMinutes: number
        /** Fallback only: the account's own language wins when it has one. */
        preferredLanguage: 'es' | 'en'
        // Identifies this turn's input. Supplying it makes the turn's writes
        // idempotent under replay (R-040); omitting it keeps random ids, which
        // is right for callers that are never retried. See
        // `agent/idempotency.ts`.
        turnKey?: string
    },
): Promise<AgentResult> => {
    const apiKey = process.env.GEMINI_API_KEY
    if (!apiKey) {
        throw new Error('GEMINI_API_KEY environment variable is not set')
    }
    const client = new GoogleGenAI({ apiKey })
    const model = process.env.GEMINI_TEXT_MODEL ?? DEFAULT_MODEL

    const contents: Content[] = args.messages.map((message) => ({
        role: message.role,
        parts: [{ text: message.text }],
    }))

    // One read for everything about the user the model needs up front: the
    // memories it is expected to apply, the currency it should assume, and
    // which gated tools this account may call.
    const turn = await ctx.runQuery(internal.agent.internal.turnContext, {
        userId: args.userId,
    })

    // The account's own language wins over the caller's guess: WhatsApp has to
    // infer one from the sender's country code (`whatsapp/linking.ts`), which
    // is wrong for anyone living outside the country that issued their number.
    // A language the user actually picked in the app is a fact, not a guess.
    const language = turn.language ?? args.preferredLanguage

    const config = {
        systemInstruction: buildTextSystemInstruction({
            nowMs: args.nowMs,
            utcOffsetMinutes: args.utcOffsetMinutes,
            preferredLanguage: language,
            defaultCurrency: turn.defaultCurrency,
            memories: turn.memories,
            exchangeRatesEnabled: turn.flags.exchangeRates,
        }),
        tools: [{ functionDeclarations: declarationsFor(turn.flags) }],
        // Gemini 3 defaults to HIGH. "Anotá $5.000 de café" does not need deep
        // reasoning, and on WhatsApp the user is staring at two grey ticks
        // while it happens — latency is part of whether this feels like a bot
        // that works. Raise it if the tool-selection quality proves too low.
        thinkingConfig: { thinkingLevel: ThinkingLevel.LOW },
    }

    let toolCalls = 0
    let lastText = ''
    // Counts calls per tool name, so the Nth `addExpense` of a replayed turn
    // maps onto the Nth `addExpense` of the original even if the reads around
    // it came out differently.
    const callsPerTool = new Map<string, number>()

    for (let round = 0; round < MAX_TOOL_ROUNDS; round += 1) {
        let response: GenerateContentResponse
        try {
            response = await client.models.generateContent({
                model,
                contents,
                config,
            })
        } catch (error) {
            // A rate limit mid-turn is not a reason to go silent — and it is
            // not a reason to retry inside the action either, since the user
            // is waiting and the quota window is measured in tens of seconds.
            // Tell them, and let their next message start a fresh turn.
            if (isTransientModelError(error)) {
                console.error(
                    `agent turn for ${args.userId} hit a transient model error: ${String(error)}`,
                )
                return {
                    text: lastText.length > 0 ? lastText : BUSY_REPLY[language],
                    toolCalls,
                    rounds: round,
                }
            }
            throw error
        }

        const modelContent = response.candidates?.[0]?.content

        const parts = modelContent?.parts ?? []

        // Text is collected from the parts rather than `response.text`, which
        // logs a warning and concatenates blindly whenever a response also
        // carries function calls — which is most of them here.
        const text = parts
            .filter((part) => part.thought !== true)
            .map((part) => part.text ?? '')
            .join('')
            .trim()
        if (text.length > 0) lastText = text

        const callParts = parts.filter(
            (part) => part.functionCall !== undefined,
        )
        if (callParts.length === 0) {
            return {
                text: text.length > 0 ? text : FALLBACK_REPLY[language],
                toolCalls,
                rounds: round + 1,
            }
        }

        // The model's turn goes back *verbatim*, not rebuilt from
        // `response.functionCalls`.
        //
        // That accessor maps each part down to its `functionCall` field and
        // drops the sibling `thoughtSignature`, which Gemini 3 requires on
        // every function call it is shown again. Reconstructing the turn gets
        // a 400: "Function call is missing a thought_signature in functionCall
        // parts" — verified against the live API, not inferred.
        if (modelContent) contents.push(modelContent)

        const responseParts: Part[] = []
        for (const part of callParts) {
            const call = part.functionCall
            if (!call) continue
            const name = call.name ?? ''
            if (toolCalls >= MAX_TOOL_CALLS) {
                responseParts.push({
                    functionResponse: {
                        id: call.id,
                        name,
                        response: {
                            ok: false,
                            error: 'Too many tool calls in one turn. Answer with what you already have.',
                        },
                    },
                })
                continue
            }
            toolCalls += 1

            // A tool that throws is a bug or an outage, not a conversation
            // event: the mutation rolled back, so the safe thing is to tell
            // the model it failed and let it apologise rather than abort the
            // turn and leave the user with silence.
            const nth = callsPerTool.get(name) ?? 0
            callsPerTool.set(name, nth + 1)

            let result: Record<string, unknown>
            try {
                const json: string = await ctx.runMutation(
                    internal.agent.tools.execute,
                    {
                        userId: args.userId,
                        name,
                        argsJson: argsToJson(call.args),
                        nowMs: args.nowMs,
                        utcOffsetMinutes: args.utcOffsetMinutes,
                        writeKey:
                            args.turnKey === undefined
                                ? undefined
                                : writeKeyFor(args.turnKey, name, nth),
                    },
                )
                result = parseToolResult(json)
            } catch (error) {
                const message =
                    error instanceof Error ? error.message : String(error)
                console.error(`agent tool ${name} threw: ${message}`)
                result = { ok: false, error: message }
            }

            responseParts.push({
                functionResponse: { id: call.id, name, response: result },
            })
        }

        contents.push({ role: 'user', parts: responseParts })
    }

    // Out of rounds. `lastText` is whatever the model last said alongside its
    // tool calls, which is usually a partial confirmation and better than the
    // generic fallback.
    console.warn(
        `agent turn for ${args.userId} hit the ${MAX_TOOL_ROUNDS}-round limit`,
    )
    return {
        text: lastText.length > 0 ? lastText : FALLBACK_REPLY[language],
        toolCalls,
        rounds: MAX_TOOL_ROUNDS,
    }
}

// Direct entry point, for exercising the agent without a phone.
//
// Internal-only: `userId` is trusted, so this must never become a public
// action. Callable from the CLI —
//   npx convex run agent/runner:runForUser '{"userId":"…","text":"gasté 500 en café"}'
// — which is how the loop, the prompt and the model name get verified without
// waiting on a WhatsApp round trip.
export const runForUser = internalAction({
    args: {
        userId: v.string(),
        text: v.string(),
        utcOffsetMinutes: v.optional(v.number()),
        preferredLanguage: v.optional(
            v.union(v.literal('es'), v.literal('en')),
        ),
    },
    handler: async (ctx, args): Promise<AgentResult> =>
        await runAgent(ctx, {
            userId: args.userId,
            messages: [{ role: 'user', text: args.text }],
            nowMs: Date.now(),
            utcOffsetMinutes: args.utcOffsetMinutes ?? -180,
            preferredLanguage: args.preferredLanguage ?? 'es',
        }),
})
