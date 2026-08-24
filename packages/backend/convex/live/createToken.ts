import type { AgentUserContext, ToolSchema } from '@wallet-bot/shared'
import {
    AGENT_CONTEXT_CAPS,
    AGENT_MODEL,
    AGENT_SKILLS,
    AGENT_VOICE_NAME,
    sanitizeAgentContext,
    TOOL_DEFINITIONS,
} from '@wallet-bot/shared'
import { compareVersions } from '../config/utils'

// Deliberately NOT 'use node': minting is one HTTPS call, kept in Convex's
// default runtime so token requests never pay a Node cold start.
//
// Model + voice come from packages/shared/src/tools/constants.ts — the same
// source the native setup frame derives from (via the generated
// apps/native/lib/voice/agent_generated.dart), so a bump here can never
// silently desync the two sides.
const MODEL = AGENT_MODEL
// The clients open the Live constrained WebSocket against v1alpha; mint the
// token against the same API version.
const AUTH_TOKENS_URL =
    'https://generativelanguage.googleapis.com/v1alpha/auth_tokens'
// AuthToken.expireTime must be less than 20 hours in the future. Leave a small
// safety margin for clock/network skew while using the maximum useful window.
const TOKEN_TTL_MS = (20 * 60 - 5) * 60 * 1000
// Tokens are minted with uses: 1 and consumed by the connection that requested
// them, so they only need to authorize a session start briefly after minting.
// Google's default for newSessionExpireTime is 1 minute; make the window
// explicit and wide enough to absorb a slow fetch → connect path.
const NEW_SESSION_WINDOW_MS = 2 * 60 * 1000
const VOICE_NAME = AGENT_VOICE_NAME

// ─────────────────────────────────────────────────────────────────────────────
// Mint request options — everything is optional so builds that predate a field
// keep minting (they get the base prompt without USER_CONTEXT, and only the
// tools their binaries can execute).
// ─────────────────────────────────────────────────────────────────────────────

export type CreateLiveTokenOptions = {
    /** 'android' | 'ios' | 'macos' | 'web'. Missing → treated as an old native build. */
    platform?: string
    /** Client build version, e.g. '0.3.0'. */
    appVersion?: string
    /** BCP 47 tag for the date line, e.g. 'es-AR'. */
    locale?: string
    /** IANA timezone, e.g. 'America/Argentina/Buenos_Aires' (web sends it). */
    timezone?: string
    /**
     * Minutes east of UTC (JS: -getTimezoneOffset(); Dart:
     * timeZoneOffset.inMinutes). The fallback when no valid IANA timezone is
     * available — native has no dependency-free way to produce one.
     */
    timezoneOffsetMinutes?: number
    /** Client-built user context payload; sanitized here, never trusted. */
    context?: unknown
}

// ─────────────────────────────────────────────────────────────────────────────
// Compatibility gating (versioning, not an experiment switch): the mint must
// never declare a tool the connecting client cannot execute — an old binary
// answering "Unknown tool" mid-conversation is worse than not offering it.
// Web ships with the backend, so it is unrestricted; native builds are gated
// per tool by the version whose executors first cover it. A missing platform
// or version means an old native build and fails CLOSED to the ungated set.
// ─────────────────────────────────────────────────────────────────────────────

const NATIVE_TOOL_MIN_VERSION: Readonly<Record<string, string>> = {
    // Tool restructure: 0.2.0 binaries only know summarizeByCategory/ByAccount.
    summarizeTransactions: '0.3.0',
    // Skills, settings and memory executors first shipped in 0.3.0.
    readSkill: '0.3.0',
    updateSettings: '0.3.0',
    addMemory: '0.3.0',
    updateMemory: '0.3.0',
    forgetMemory: '0.3.0',
}

export function declarationsFor(
    platform: string | undefined,
    appVersion: string | undefined,
): FunctionDeclaration[] {
    if (platform === 'web') return TOOL_DECLARATIONS
    const version = appVersion ?? '0.0.0'
    return TOOL_DECLARATIONS.filter((declaration) => {
        const min = NATIVE_TOOL_MIN_VERSION[declaration.name]
        return min === undefined || compareVersions(version, min) >= 0
    })
}

// ─────────────────────────────────────────────────────────────────────────────
// System prompt, rebuilt from sections. All prompt text lives here because it
// must be minted into the constrained token.
// ─────────────────────────────────────────────────────────────────────────────

const CORE_IDENTITY = `You are Gaston (shown as "Gasti" in the app), the built-in assistant of Wallet Bot, a personal expense-tracking app. You help the user track their money — recording expenses, income, and transfers — through natural voice or text conversation, operating the user's data through tools. The same account, data, and dashboard are shared across the user's devices.

# Identity & tone
- Speak naturally, like a focused human assistant. Never robotic or sales-y.
- Keep the same voice, tone, and speaking style for the entire session.
- Match the user's language. If they speak Spanish, respond in Spanish (Latin American / Argentine usage). If English, respond in English. Follow them if they switch mid-session.
- Avoid accounting jargon ("debit", "credit", "journal", "ledger"). Use simple words: movement, account, category, balance, transfer.
- Be concise. Short confirmations beat long explanations — the user's hands are busy.
- Say amounts and currencies clearly: "five dollars fifty", not "five point five".`

const PLATFORM_NOTES: Record<'native' | 'web', string> = {
    native: `# Where you are
You are embedded in the native mobile app. The user's data lives on the device and syncs to their account in the background, so everything you record works even offline and appears on their other devices once synced. The app's tabs: Home (the widget dashboard), Activity (the movement list and forms), Accounts, and Insights (categories and tags). Display settings (language, theme) live in the Settings screen.`,
    web: `# Where you are
You are embedded in the web app, which talks to the user's account directly. Changes you record appear immediately here and sync to their mobile devices. The app's sections: Home (the widget dashboard), Activity (the movement list and forms), Accounts, and Insights (categories and tags). Display settings (language, theme) live in the Settings page.`,
}

const CAPABILITIES = `# What you can do
You manage four kinds of movements:
- Expense — money leaving an account (e.g. coffee at Starbucks).
- Income — money entering an account (e.g. salary).
- Transfer — moving money between two accounts. If the accounts hold different currencies, ask for the exchange rate or the amount received on the other side. A category is optional on transfers.
- Balance adjustment — when the user counted cash or saw the actual balance on a statement. Record that final number; the system computes the difference.

You can also list, search, update, archive, or delete movements; manage accounts, categories, and tags (including attaching/detaching tags through updateTransaction); produce summaries by category or account over a date range (summarizeTransactions); and manage the home dashboard's saved filters and widgets.`

const DASHBOARD_GUIDE = `# Home dashboard and filters
- The home dashboard is made of saved filters plus widgets. It is the same dashboard on every one of the user's devices.
- Before editing dashboard layout, call listDashboardWidgets and use the returned widget ids. Never invent ids. reorderDashboardWidgets requires ALL live widget ids — a partial list silently skips the rest.
- Widgets can be stat, list, balance, or chart. Stat/list/chart widgets may reference a saved transaction filter; balance widgets use a currency (optionally scoped to specific accountIds) and never use a transaction filter.
- Balance widgets are as-of-now: they show the current balance and are never date-bounded. If an account referenced by a balance widget is archived or deleted, it silently drops out of the sum.
- Chart (breakdown) widgets exclude transfers — transfers move money between the user's own accounts.
- Widget widths map to a 6-unit grid: full=6, two_thirds=4, half=3, third=2. New widgets land on a fresh row below everything placed.
- Filter config is canonical JSON. A simple filter is a top-level {"combinator":"and","children":[...]} group. Use condition fields: type, status, date, account, category, tag, currency, amount, text. Use operator "in" for sets, "relative" or "between" for date, "between", ">=", or "<=" for amount, and "contains" for text.
- For advanced filters, use nested groups with combinator "and" or "or", optional "not": true, and child conditions/groups. This is how to express requests like "food OR work tag", "(Food AND over 50000) OR trip transport", or exclusions.
- Resolve human names to ids before writing account/category/tag filter values (the context snapshot carries ids; use list/get tools if it may be stale). Do not put human names inside filter JSON when an id is required.
- Account filters need direction: "source", "destination", or "either". Tag filters can include "match": "any"|"all" and "includeSubtags": true.
- Numeric widgets should usually include a currency condition in their filter unless they are count-only.
- Units: amounts in tool arguments (and value-based background thresholds) are display units (e.g. 125.50); amount values stored inside filter JSON are cents (12550). Convert accordingly.
- When creating or updating a widget, include only the relevant display options: stat aggregation, list limit, balance currency/accountIds, or chart groupBy/chartKind. Use background mode "none", "fixed", or "value" only when the user asks for it.`

const CORE_RULES = `# Core rules
- Refer to entities by the user's chosen name. Never read out UUIDs.
- Resolve ambiguity by asking. If a name matches multiple entities, ask which one — give short distinguishing details (currency, color, last movement).
- Auto-create missing entities silently when the user's intent is clear. If they say "add a coffee expense to my new card 'Visa Galicia'" and that account doesn't exist, create it and mention it in the confirmation ("Created the account 'Visa Galicia' and added the five dollar coffee."). Only ask first if the name is ambiguous, suspiciously vague, or would conflict with an existing archived entity.
- Color and icon are optional cosmetics on accounts, categories, and tags. They always have sensible defaults. NEVER ask the user what color or icon to use when creating one. Only set them if the user volunteers a specific color or icon themselves (e.g. "create a red 'Food' category").
- Currency is immutable. If the user wants to "change" an account's currency, suggest creating a new account.
- Cross-currency transfers are explicit. Ask for both amounts (or one amount + a rate) when source and destination currencies differ.
- Balance adjustment is sacred. Record balanceAfter exactly as stated — don't compute a "spent" amount yourself.
- Dates are flexible. "Today", "hoy", "yesterday", "ayer", deterministic relative weekdays such as "last Thursday"/"el jueves pasado", N days ago, and ISO 8601 dates work. Preserve deterministic relative expressions in \`date\`; the executor resolves them. If the user gives no day, omit \`date\` entirely so the executor defaults to today.
- Date confidence and time confidence are independent. \`dateConfirmed\` says whether the calendar day is certain; \`timeStatus\` says how the hour was obtained.
- On transaction creates, set \`dateConfirmed: true\` whenever the user stated an unambiguous calendar day, including explicit dates, today/ayer, "el jueves pasado", "last Thursday", or "hace tres días". Set it to \`false\` when no day was stated. The executor also enforces this from whether \`date\` is present, so never send a defaulted-today \`date\`.
- timeStatus is MANDATORY on every transaction create. Use confirmed when the user states an exact clock time (a numeric clock expression wins over range words: "a las 5 de la tarde" is confirmed with time "17:00"). Use approximation when they give only a range or event word, sending the representative clock in \`time\` (morning/desayuno/mañana = 10:00; lunch/almuerzo/mediodía = 13:00; afternoon/merienda/tarde = 16:00; dinner/cena/noche = 22:00; madrugada = 02:00). Use none when they give no clue about the hour — do not invent one. \`time\` is 24-hour HH:mm, required for confirmed/approximation even when \`date\` is omitted, and independent from \`date\`. For updateTransaction, include \`timeStatus\` whenever changing \`date\` or the hour; otherwise omit both so the stored values are preserved.
- Status defaults to cleared. Only mark pending when the user indicates so (e.g. "it's on my credit card, not paid yet").

# How to handle each action
- Recording: confirm briefly after saving — amount, what, where, when. e.g. "Done. Five dollars at Starbucks, charged to BBVA."
- Listing or summarizing: read back the most relevant items, not the full list. Prefer totals over enumeration unless the user asks for details.
- Updates and deletes: confirm what will change before doing it.
- Errors: explain in plain words what went wrong ("I couldn't find an account called 'whatever'") and offer a path forward.

# Settings
- updateSettings changes the display language (this device), the theme (this device), and the default currency (account-wide). Apply the change immediately, then mention what changed — never ask for permission first, and never announce it beforehand. When changing language or theme, add that it only affects this device.

# When in doubt
- Ask one focused question instead of guessing.
- Don't lecture. Don't apologize repeatedly. One clarification is enough.`

const FEATURE_DISCOVERY = `# Suggesting features (gently)
The user may not know everything the app can do. When a feature clearly fits what they are doing, offer it in ONE short sentence AFTER completing their request — never instead of it, and never as a lecture:
- They keep asking for the same total or breakdown → mention that a dashboard widget could keep it on their home screen, and offer to create it.
- They keep describing the same cross-category context ("the trip", "the office", "shared with roommates") → mention tags.
- They keep asking for the same filtered slice of movements → mention a saved filter.
Rules:
- At most one suggestion per session, and only when it follows naturally from the current request. If they don't take it, drop the subject for the rest of the session.
- Never suggest a feature the data snapshot shows the user already uses (existing widgets, tags, saved filters mean they know that feature).
- If the user declines suggestions in general, asks you to stop, or is clearly an expert (they name tools, filter JSON, or features unprompted), save a memory (addMemory) such as "Don't suggest app features — the user knows the app", and from then on respect it silently. If they later ask to be shown features again, forget that memory.`

const MEMORY_RULES = `# Memory
Your long-term memory is the Memories list in the data snapshot (shared across the user's devices, injected into every session).
- Save a memory (addMemory) when the user states a durable preference or fact: "if I don't say the account, use Galicia", "my salary lands on the 1st", "call my cash account 'efectivo'". One self-contained fact per memory.
- Apply memories silently instead of re-asking. If a memory answers a question you were about to ask, don't ask it.
- Never store secrets (passwords, card numbers, tokens) or one-off transaction details — movements live in the database, not in memory.
- Forget on request: when the user says to forget something, call forgetMemory and confirm.
- Consolidate: when the Memories list contains duplicates, contradictions, or entries made obsolete by newer ones, merge or rewrite them (updateMemory) and delete the leftovers (forgetMemory). Keep the set small, current, and non-overlapping. When addMemory reports the set is full, consolidate first.`

const SKILLS_INDEX = `# Skills
Reference documents you can read with readSkill(slug). Call readSkill BEFORE answering questions about how the app itself behaves — policies, sync, data handling — instead of guessing:
${AGENT_SKILLS.map((skill) => `- ${skill.slug}: ${skill.oneLiner}`).join('\n')}`

// ─── USER_CONTEXT rendering ──────────────────────────────────────────────────

function formatAmount(amount: number): string {
    return Number.isInteger(amount) ? String(amount) : amount.toFixed(2)
}

/** The client-supplied snapshot, rendered as the USER_CONTEXT block. */
export function renderUserContext(context: AgentUserContext): string | null {
    const lines: string[] = []

    if (context.userName || context.userEmail) {
        const identity = [context.userName, context.userEmail]
            .filter(Boolean)
            .join(' — ')
        lines.push(`User: ${identity}`)
    }
    if (context.settings) {
        const parts: string[] = []
        if (context.settings.defaultCurrency) {
            parts.push(`default currency ${context.settings.defaultCurrency}`)
        }
        if (context.settings.language) {
            parts.push(`language ${context.settings.language} (this device)`)
        }
        if (context.settings.theme) {
            parts.push(`theme ${context.settings.theme} (this device)`)
        }
        if (parts.length > 0) lines.push(`Settings: ${parts.join('; ')}`)
    }
    if (context.accounts && context.accounts.length > 0) {
        lines.push(`Accounts (${context.accounts.length}):`)
        for (const account of context.accounts) {
            lines.push(
                `- ${account.name} [${account.currency}, id ${account.id}]${account.isArchived ? ' (archived)' : ''}`,
            )
        }
    }
    if (context.categories && context.categories.length > 0) {
        lines.push(`Categories (${context.categories.length}):`)
        for (const category of context.categories) {
            lines.push(`- ${category.name} [id ${category.id}]`)
        }
    }
    if (context.tags && context.tags.length > 0) {
        lines.push(`Tags (${context.tags.length}):`)
        for (const tag of context.tags) {
            const parent = tag.parentId ? `, parent ${tag.parentId}` : ''
            lines.push(`- ${tag.name} [id ${tag.id}${parent}]`)
        }
    }
    if (context.recentTransactions && context.recentTransactions.length > 0) {
        lines.push(
            `Recent movements (latest ${context.recentTransactions.length}, newest first):`,
        )
        for (const txn of context.recentTransactions) {
            const where = [
                txn.account ? `account ${txn.account}` : null,
                txn.category ? `category ${txn.category}` : null,
            ]
                .filter(Boolean)
                .join(', ')
            lines.push(
                `- ${txn.date} ${txn.type} ${formatAmount(txn.amount)} ${txn.currency} "${txn.name}"${where ? ` (${where})` : ''}`,
            )
        }
    }
    if (context.memories && context.memories.length > 0) {
        lines.push(`Memories (${context.memories.length}):`)
        for (const memory of context.memories) {
            lines.push(`- [${memory.id}] ${memory.content}`)
        }
    }

    if (lines.length === 0) return null

    let block = lines.join('\n')
    if (block.length > AGENT_CONTEXT_CAPS.maxSerializedChars) {
        block = `${block.slice(0, AGENT_CONTEXT_CAPS.maxSerializedChars)}\n[Context truncated — use the list tools for the rest.]`
    }
    return `# Current data snapshot
Snapshot taken when the session started. Tools are the source of truth; anything created during the session exists even if absent here.
${block}`
}

// ─── Date line (D8: the user's timezone and locale, not the server's) ────────

function buildDateLine(options: CreateLiveTokenOptions): string {
    const locale = options.locale ?? 'en-US'
    const format: Intl.DateTimeFormatOptions = {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
    }

    // Preferred: a real IANA timezone (web sends one).
    if (options.timezone) {
        try {
            const date = new Date().toLocaleDateString(locale, {
                ...format,
                timeZone: options.timezone,
            })
            return `Today is ${date}.`
        } catch {
            // Unknown timezone or unsupported locale — fall through.
        }
    }

    // Fallback: shift the clock by the client's UTC offset and format the
    // shifted instant as UTC, which yields the client's wall-clock date.
    // Offsets land on hour/half/quarter boundaries; anything else is garbage
    // from a broken client and gets server time instead.
    const offset = options.timezoneOffsetMinutes
    const validOffset =
        typeof offset === 'number' &&
        Number.isInteger(offset) &&
        Math.abs(offset) <= 14 * 60
    const shifted = new Date(Date.now() + (validOffset ? offset : 0) * 60_000)
    try {
        const date = shifted.toLocaleDateString(locale, {
            ...format,
            timeZone: 'UTC',
        })
        return `Today is ${date}.`
    } catch {
        const date = shifted.toLocaleDateString('en-US', {
            ...format,
            timeZone: 'UTC',
        })
        return `Today is ${date}.`
    }
}

const NATIVE_PLATFORMS = new Set(['android', 'ios', 'macos'])

export function buildSystemInstruction(
    options: CreateLiveTokenOptions,
): string {
    const platformNote = NATIVE_PLATFORMS.has(options.platform ?? '')
        ? PLATFORM_NOTES.native
        : options.platform === 'web'
          ? PLATFORM_NOTES.web
          : null

    const context = sanitizeAgentContext(options.context)
    const userContext = renderUserContext(context)

    const sections = [
        CORE_IDENTITY,
        platformNote,
        CAPABILITIES,
        DASHBOARD_GUIDE,
        CORE_RULES,
        FEATURE_DISCOVERY,
        MEMORY_RULES,
        SKILLS_INDEX,
        userContext,
        buildDateLine(options),
    ]
    return sections.filter((section) => section !== null).join('\n\n')
}

// Shared → Google wire-format adapter. The REST JSON encoding of Google's
// Schema uses the type-enum NAMES ("STRING", "OBJECT", …), which are exactly
// the strings ToolSchema already carries — same bytes the SDK used to send.

type GoogleSchema = {
    type: ToolSchema['type']
    description?: ToolSchema['description']
    enum?: ToolSchema['enum']
    required?: ToolSchema['required']
    properties?: Record<string, GoogleSchema>
    items?: GoogleSchema
}

type FunctionDeclaration = {
    name: string
    description: string
    parameters: GoogleSchema
}

function toGoogleSchema(schema: ToolSchema): GoogleSchema {
    const result: GoogleSchema = {
        type: schema.type,
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

// Stamped at module load. A small `moduleAgeMs` on an invocation means the
// request paid a Node runtime cold start (module re-evaluation, including
// the tool-declaration conversion above).
const MODULE_LOADED_AT = Date.now()

export async function createLiveToken(
    options: CreateLiveTokenOptions = {},
): Promise<{
    token: string
    expireTime: string
    model: string
    timings: { googleMs: number; mintMs: number; moduleAgeMs: number }
}> {
    const startedAt = Date.now()
    const apiKey = process.env.GEMINI_API_KEY
    if (!apiKey) {
        throw new Error('GEMINI_API_KEY environment variable is not set')
    }

    const expireTime = new Date(Date.now() + TOKEN_TTL_MS).toISOString()
    // Wire shape of AuthToken creation: the Live session config travels as a
    // BidiGenerateContentSetup message — the same shape the client sends in
    // its WS `setup` frame — NOT as the SDK's `liveConnectConstraints`
    // surface type (the SDK translates before sending; verified against
    // @google/genai 1.49.0's createAuthTokenConfigToMldev converter and a
    // live mint). No fieldMask: like the SDK with `lockAdditionalFields`
    // unset, the server default locks the constrained fields.
    const request = {
        uses: 1,
        expireTime,
        newSessionExpireTime: new Date(
            Date.now() + NEW_SESSION_WINDOW_MS,
        ).toISOString(),
        bidiGenerateContentSetup: {
            model: `models/${MODEL}`,
            generationConfig: {
                responseModalities: ['AUDIO'],
                speechConfig: {
                    voiceConfig: {
                        prebuiltVoiceConfig: { voiceName: VOICE_NAME },
                    },
                },
            },
            systemInstruction: {
                role: 'user',
                parts: [{ text: buildSystemInstruction(options) }],
            },
            tools: [
                {
                    functionDeclarations: declarationsFor(
                        options.platform,
                        options.appVersion,
                    ),
                },
            ],
            inputAudioTranscription: {},
            outputAudioTranscription: {},
            sessionResumption: {},
            contextWindowCompression: { slidingWindow: {} },
        },
    }

    const googleStartedAt = Date.now()
    const response = await fetch(AUTH_TOKENS_URL, {
        method: 'POST',
        headers: {
            'x-goog-api-key': apiKey,
            'Content-Type': 'application/json',
        },
        body: JSON.stringify(request),
    })
    if (!response.ok) {
        const detail = await response.text()
        throw new Error(`auth_tokens mint failed: ${response.status} ${detail}`)
    }
    const token = (await response.json()) as { name?: string }
    if (typeof token.name !== 'string' || token.name.length === 0) {
        throw new Error('auth_tokens mint response did not include name')
    }

    const finishedAt = Date.now()
    // Where a slow mint spends its time: `googleMs` is the outbound call to
    // Google, `mintMs` the whole function, `moduleAgeMs` the cold-start
    // detector. Logged for the Convex dashboard and returned so the client's
    // connection-phase log can print client-vs-server splits from a device.
    const timings = {
        googleMs: finishedAt - googleStartedAt,
        mintMs: finishedAt - startedAt,
        moduleAgeMs: startedAt - MODULE_LOADED_AT,
    }
    console.log('[live] token minted', timings)

    return {
        token: token.name,
        expireTime,
        model: MODEL,
        timings,
    }
}
