import { z } from 'zod'

// Zod schemas (source of truth)

const transactionType = z.enum(['expense', 'income', 'transfer'])

export const toolSchemas = {
    addTransaction: z.object({
        type: transactionType.describe('Transaction type'),
        amount: z
            .number()
            .describe('The amount (e.g. 12.50 for twelve and fifty cents)'),
        description: z
            .string()
            .describe('Brief description of the transaction'),
    }),
    listTransactions: z.object({
        type: transactionType.optional().describe('Filter by type. Optional.'),
    }),
    listAccounts: z.object({}),
} satisfies Record<string, z.ZodType>
