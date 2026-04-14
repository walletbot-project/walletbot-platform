import type { ToolName } from '@wallet-bot/shared'
import { toolSchemas } from '@wallet-bot/shared'
import { defineTool, type ToolExecutor } from './helpers'

export const toolExecutors = {
    addTransaction: defineTool(toolSchemas.addTransaction, async () => {
        return { success: true, message: 'Mock: transaction added' }
    }),
    listTransactions: defineTool(toolSchemas.listTransactions, async () => {
        return { transactions: [], count: 0 }
    }),
    listAccounts: defineTool(toolSchemas.listAccounts, async () => {
        return { accounts: [] }
    }),
} satisfies Record<ToolName, ToolExecutor>
