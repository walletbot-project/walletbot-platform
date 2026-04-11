'use node'

import { GoogleGenAI, Modality, Type } from '@google/genai'
import { action } from '../_generated/server'
import { VALID_CATEGORIES } from '../expenses/constants'

const MODEL = 'gemini-3.1-flash-live-preview'
const TOKEN_TTL_MS = 30 * 60 * 1000 // 30 minutes

const SYSTEM_INSTRUCTION = `You are a personal expense tracking assistant. You help the user manage their expenses through voice.

CAPABILITIES — you can:
• Add new expenses (addExpense)
• Edit existing expenses — change amount, description, category, currency, or date (updateExpense). Always list expenses first to get the ID.
• Delete expenses (deleteExpense). Always list expenses first to get the ID.
• List expenses with optional date range and/or category filter (listExpenses)
• Get a spending summary with totals and category breakdown, optionally filtered by date range and/or category (getExpenseSummary)

CATEGORIES: groceries, transport, dining, entertainment, utilities, health, shopping, other.

CURRENCIES: USD (US dollars) or ARS (Argentine pesos). Default to USD unless the user says "pesos" or "ARS".

RULES:
• When the user mentions spending money, add the expense immediately.
• When the user asks to see, find, or search expenses, use listExpenses. Use the category and date filters when the user specifies them (e.g. "show me dining expenses from last week").
• When the user asks "how much did I spend on X", use getExpenseSummary with the appropriate category/date filters.
• For edit or delete operations, call listExpenses first so you have the expense ID, then call updateExpense or deleteExpense.
• Always confirm after adding, editing, or deleting an expense. Include the amount with currency.
• Keep responses short and conversational.`

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

const updateExpenseTool: FunctionDeclaration = {
    name: 'updateExpense',
    description:
        'Update an existing expense. Use listExpenses first to find the expense ID. Only include the fields you want to change.',
    parameters: {
        type: Type.OBJECT,
        properties: {
            expenseId: {
                type: Type.STRING,
                description: 'The ID of the expense to update',
            },
            amount: {
                type: Type.NUMBER,
                description:
                    'New amount (e.g. 12.50 for twelve and fifty cents). Only if changing.',
            },
            currency: {
                type: Type.STRING,
                description: 'New currency code. Only if changing.',
                enum: ['USD', 'ARS'],
            },
            description: {
                type: Type.STRING,
                description: 'New description. Only if changing.',
            },
            category: {
                type: Type.STRING,
                description: 'New category. Only if changing.',
                enum: [...VALID_CATEGORIES],
            },
            date: {
                type: Type.STRING,
                description: 'New date in YYYY-MM-DD format. Only if changing.',
            },
        },
        required: ['expenseId'],
    },
}

const deleteExpenseTool: FunctionDeclaration = {
    name: 'deleteExpense',
    description:
        'Delete an expense by its ID. Use listExpenses first to find the expense ID.',
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
        'List expenses. Supports filtering by date range and/or category. Call this when the user asks to see, find, or search their expenses.',
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
            category: {
                type: Type.STRING,
                description: 'Filter by category. Optional.',
                enum: [...VALID_CATEGORIES],
            },
        },
        required: [],
    },
}

const getExpenseSummaryTool: FunctionDeclaration = {
    name: 'getExpenseSummary',
    description:
        'Get a spending summary with total amount and breakdown by category. Supports filtering by date range and/or category. Call this when the user asks "how much did I spend" or wants totals.',
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
            category: {
                type: Type.STRING,
                description: 'Filter summary to a single category. Optional.',
                enum: [...VALID_CATEGORIES],
            },
        },
        required: [],
    },
}

const TOOL_DECLARATIONS: FunctionDeclaration[] = [
    addExpenseTool,
    updateExpenseTool,
    deleteExpenseTool,
    listExpensesTool,
    getExpenseSummaryTool,
]

export const requestLiveToken = action({
    args: {},
    handler: async (ctx) => {
        const identity = await ctx.auth.getUserIdentity()
        if (!identity) {
            throw new Error('Unauthenticated')
        }

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
