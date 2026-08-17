// Which of the shared tools the text-channel agent is allowed to call.
//
// Kept free of `@google/genai` (that adapter lives in `agent/schema.ts`) so the
// executor mutation, which runs in the default runtime, can import the same
// list the model is given. Two sources of truth for "what tools exist" is how
// you end up with a model that calls something the executor cannot dispatch.

import type { ToolName } from '@wallet-bot/shared'

// The nine dashboard/saved-filter tools are deliberately absent.
//
// They exist for the native home screen: `createDashboardWidget` has to place
// a tile on a grid, and that packing lives in Dart
// (`components/dashboard/dashboard_layout.dart`), with no server-side
// equivalent. A WhatsApp user also cannot see the result. Rather than ship a
// half-working port, the prompt tells the agent to send the user to the app.
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
    'getRecentTransactions',
    // Transactions: write
    'addExpense',
    'addIncome',
    'addTransfer',
    'addBalanceAdjustment',
    'updateTransaction',
    'deleteTransaction',
    'tagTransaction',
    'untagTransaction',
    // Summaries
    'summarizeByCategory',
    'summarizeByAccount',
] as const satisfies readonly ToolName[]

export type AgentToolName = (typeof AGENT_TOOL_NAMES)[number]

const ALLOWED = new Set<string>(AGENT_TOOL_NAMES)

export const isAgentToolName = (name: string): name is AgentToolName =>
    ALLOWED.has(name)
