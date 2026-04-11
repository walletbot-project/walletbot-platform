'use node'

import { GoogleGenAI, Modality, Type } from '@google/genai'
import { action } from '../_generated/server'
import { VALID_CATEGORIES } from '../expenses/constants'

const MODEL = 'gemini-3.1-flash-live-preview'
const TOKEN_TTL_MS = 30 * 60 * 1000 // 30 minutes

const SYSTEM_INSTRUCTION =
    'You are a personal expense tracking assistant. Help the user track their spending by adding expenses, listing recent expenses, deleting expenses, and summarizing their spending. When the user mentions spending money, use the addExpense tool. When they ask about their expenses, use listExpenses or getExpenseSummary as appropriate. When they ask to delete an expense, use deleteExpense. Always confirm after adding or deleting an expense. The user can track expenses in USD (US dollars) or ARS (Argentine pesos). Default to USD unless the user says pesos or ARS. Always include the currency when confirming.'

import type { FunctionDeclaration } from '@google/genai'

const addExpenseTool: FunctionDeclaration = {
    name: 'addExpense',
    description:
        'Add a new personal expense. Call this when the user mentions spending money on something.',
    parameters: {
        type: Type.OBJECT,
        properties: {
            amount: {
                type: Type.NUMBER,
                description:
                    'The expense amount (e.g. 12.50 for twelve and fifty cents)',
            },
            currency: {
                type: Type.STRING,
                description:
                    'Currency code. Use "USD" for US dollars, "ARS" for Argentine pesos. Defaults to USD.',
                enum: ['USD', 'ARS'],
            },
            description: {
                type: Type.STRING,
                description: 'Brief description of what the expense was for',
            },
            category: {
                type: Type.STRING,
                description: 'Expense category',
                enum: [...VALID_CATEGORIES],
            },
            date: {
                type: Type.STRING,
                description:
                    'Date of the expense in YYYY-MM-DD format. Defaults to today if not specified.',
            },
        },
        required: ['amount', 'description', 'category'],
    },
}

const deleteExpenseTool: FunctionDeclaration = {
    name: 'deleteExpense',
    description:
        'Delete an expense by its ID. Call this when the user asks to remove or delete a specific expense. Use listExpenses first to find the expense ID if needed.',
    parameters: {
        type: Type.OBJECT,
        properties: {
            expenseId: {
                type: Type.STRING,
                description: 'The ID of the expense to delete',
            },
        },
        required: ['expenseId'],
    },
}

const listExpensesTool: FunctionDeclaration = {
    name: 'listExpenses',
    description:
        'List recent expenses. Call this when the user asks to see their expenses or spending history.',
    parameters: {
        type: Type.OBJECT,
        properties: {
            startDate: {
                type: Type.STRING,
                description:
                    'Start date for filtering in YYYY-MM-DD format. Optional.',
            },
            endDate: {
                type: Type.STRING,
                description:
                    'End date for filtering in YYYY-MM-DD format. Optional.',
            },
        },
        required: [],
    },
}

const getExpenseSummaryTool: FunctionDeclaration = {
    name: 'getExpenseSummary',
    description:
        'Get a summary of expenses including total amount and breakdown by category. Call this when the user asks about their spending summary, totals, or category breakdown.',
    parameters: {
        type: Type.OBJECT,
        properties: {
            startDate: {
                type: Type.STRING,
                description:
                    'Start date for the summary period in YYYY-MM-DD format. Optional.',
            },
            endDate: {
                type: Type.STRING,
                description:
                    'End date for the summary period in YYYY-MM-DD format. Optional.',
            },
        },
        required: [],
    },
}

const TOOL_DECLARATIONS: FunctionDeclaration[] = [
    addExpenseTool,
    deleteExpenseTool,
    listExpensesTool,
    getExpenseSummaryTool,
]

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
                        systemInstruction: SYSTEM_INSTRUCTION,
                        tools: [{ functionDeclarations: TOOL_DECLARATIONS }],
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
