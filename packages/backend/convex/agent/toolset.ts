// Which of the shared tools the text-channel agent is allowed to call.
//
// Kept free of `@google/genai` (that adapter lives in `agent/schema.ts`) so the
// executor mutation, which runs in the default runtime, can import the same
// list the model is given. Two sources of truth for "what tools exist" is how
// you end up with a model that calls something the executor cannot dispatch.

import type { ToolName } from '@wallet-bot/shared'
import type { FlagKey } from '../featureFlags/utils'

// The nine dashboard/saved-filter tools are deliberately absent.
//
// They exist for the home screen: `createDashboardWidget` has to place a tile
// on a grid, and that packing lives in Dart
// (`components/dashboard/dashboard_layout.dart`) and in the web app, with no
// server-side equivalent. A WhatsApp user also cannot see the result. Rather
// than ship a half-working port, the prompt tells the agent to send the user
// to the app.
//
// `updateSettings` is absent for the same kind of reason: two of its three
// fields (language, theme) are display preferences scoped to the device the
// agent is running on, and a WhatsApp turn has no device. Honouring only
// `defaultCurrency` would mean the tool means something different here than
// everywhere else.
export const AGENT_TOOL_NAMES = [
    // Accounts
    'listAccounts',
    'getAccount',
    'getAccountBalance',
    'createAccount',
    'updateAccount',
    'archiveAccount',
    // Categories
    'listCategories',
    'getCategory',
    'createCategory',
    'updateCategory',
    'archiveCategory',
    // Tags
    'listTags',
    'getTag',
    'createTag',
    'updateTag',
    'archiveTag',
    // Transactions: read
    'listTransactions',
    'getTransaction',
    // Transactions: write
    'addExpense',
    'addIncome',
    'addTransfer',
    'addBalanceAdjustment',
    'updateTransaction',
    'deleteTransaction',
    // Summaries
    'summarizeTransactions',
    // Agent memory
    'addMemory',
    'updateMemory',
    'forgetMemory',
    // Math & dates
    'calculate',
    'calculateDate',
    // Skills
    'readSkill',
    // Exchange rates
    'getExchangeRate',
] as const satisfies readonly ToolName[]

export type AgentToolName = (typeof AGENT_TOOL_NAMES)[number]

// Tools behind a feature flag, resolved server-side for the conversation's
// user. The voice channel gates the same tool the same way
// (`live/createToken.ts`), so a rollout that has not reached this user cannot
// be reached through WhatsApp either.
export const FLAG_GATED_TOOLS: Readonly<
    Partial<Record<AgentToolName, FlagKey>>
> = {
    getExchangeRate: 'exchangeRates',
}

const ALLOWED = new Set<string>(AGENT_TOOL_NAMES)

export const isAgentToolName = (name: string): name is AgentToolName =>
    ALLOWED.has(name)

/** The flag a tool is gated behind, or undefined when it is always available. */
export const flagForTool = (name: AgentToolName): FlagKey | undefined =>
    FLAG_GATED_TOOLS[name]
