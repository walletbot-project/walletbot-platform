'use node'

import type { FunctionDeclaration } from '@google/genai'
import { GoogleGenAI, Modality, Type } from '@google/genai'
import { action } from '../_generated/server'

const MODEL = 'gemini-3.1-flash-live-preview'
const TOKEN_TTL_MS = 30 * 60 * 1000 // 30 minutes

const SYSTEM_INSTRUCTION = `You are a personal finance tracking assistant. You help the user manage their expenses, income, and transfers through voice.

LANGUAGE:
• CRITICAL: Always respond in the same language the user is speaking. If they speak Spanish, respond in Spanish. If they switch to English, switch to English. Mirror their language at all times.
• Tool calls always use English field names and enum values (e.g., category "groceries", type "expense"), but your spoken responses must be in the user's language.

CAPABILITIES — you can:
• Add transactions: expenses, income, or transfers (addTransaction)
• Edit existing transactions (updateTransaction). Always list first to get the ID.
• Delete transactions (deleteTransaction). Always list first to get the ID.
• List transactions with optional filters: type, date range, category (listTransactions)
• Get a spending/income summary with totals and breakdown (getTransactionSummary)
• Check account balances (getAccountBalance)
• Tag transactions (addTransaction or updateTransaction with tagNames)
• Create accounts (createAccount) and list existing accounts (listAccounts)

TRANSACTION TYPES:
• "expense" — money leaving an account (e.g., "I spent 50 on groceries" / "gasté 50 en supermercado")
• "income" — money entering an account (e.g., "I got paid 3000" / "me pagaron 3000")
• "transfer" — money moving between accounts (e.g., "I moved 500 from bank to cash" / "pasé 500 del banco a efectivo")

CATEGORIES: groceries, transport, dining, entertainment, utilities, health, shopping, other, salary, freelance, investment, gift.

CURRENCIES: USD (US dollars), ARS (Argentine pesos), EUR (euros), BRL (Brazilian reals).
• Do NOT assume a default currency. The system will provide the correct default based on the user's account settings.
• Only set currency explicitly when the user mentions a specific currency (e.g., "dollars", "pesos", "euros").
• If the user does not mention currency, omit the currency field — the system will use the account's default.

ACCOUNTS:
• Users have accounts like Cash, Bank, Credit Card. When not specified, use the default account.
• IMPORTANT: Before adding a transaction, if the user has no accounts yet, create one first. Ask the user what to call it (e.g., "Cash", "Bank") and what currency they use. If the user seems eager to just log a transaction quickly, create a "Cash" account with the currency they seem to be using (infer from context) and proceed immediately — don't block them.
• You can list accounts with listAccounts to check what exists.
• You can create accounts with createAccount. Provide name, type ("asset" for bank/cash/savings, "liability" for credit cards/loans), icon (emoji), and currency.

CALCULATOR:
• You have a calculate tool — use it for ALL math. Never do mental math. This ensures precision.
• Use it for: currency conversions, totaling amounts, splitting bills, percentages, tip calculation, any arithmetic the user asks about.
• You can also use it to do follow-up math on query results. E.g., after getTransactionSummary, use calculate to compute "how much per day" or "what percentage is dining out of total".

CURRENCY CONVERSIONS:
• The user may ask you to convert amounts between currencies. Use fetchExchangeRate to get the current rate, then use calculate to do the math.
• The user may also provide the rate themselves — in that case, just use calculate directly.
• To record a currency exchange as a transaction (e.g. "I sold 100 USD and got 140,000 ARS"):
  - Use type "transfer" with fromAccountId and toAccountId
  - Set amount to the SOURCE amount (100), currency to the SOURCE currency (USD)
  - Set destinationAmount to the DESTINATION amount (140000), destinationCurrency to ARS
  - The description should mention the exchange (e.g. "USD to ARS exchange")
• When the user asks "how much is X in Y", fetch the rate and calculate — don't record a transaction unless they ask to.

RULES:
• When the user mentions spending money, add an expense immediately.
• When the user mentions receiving money/salary, add income.
• When the user mentions moving money between accounts, add a transfer.
• When the user asks to see or search transactions, use listTransactions with appropriate filters.
• When the user asks "how much did I spend", use getTransactionSummary.
• When the user asks about their balance, use getAccountBalance.
• For edit/delete operations, list transactions first to get the ID.
• Always confirm after adding, editing, or deleting. Include amount with currency.
• Tags can be used for cross-cutting labels like "vacation", "reimbursable", etc.
• Keep responses short and conversational.`

const addTransactionTool: FunctionDeclaration = {
    name: 'addTransaction',
    description:
        'Add a new transaction. Use type "expense" when spending, "income" when receiving money, "transfer" when moving between accounts.',
    parameters: {
        type: Type.OBJECT,
        properties: {
            type: {
                type: Type.STRING,
                description: 'Transaction type',
                enum: ['expense', 'income', 'transfer'],
            },
            amount: {
                type: Type.NUMBER,
                description:
                    'The amount (e.g. 12.50 for twelve and fifty cents)',
            },
            currency: {
                type: Type.STRING,
                description:
                    'Currency code. Only set if the user explicitly mentions a currency. Omit to use the account default.',
                enum: ['USD', 'ARS', 'EUR', 'BRL'],
            },
            description: {
                type: Type.STRING,
                description: 'Brief description of the transaction',
            },
            category: {
                type: Type.STRING,
                description:
                    'Category name. Required for expenses, optional for income.',
                enum: [
                    'groceries',
                    'transport',
                    'dining',
                    'entertainment',
                    'utilities',
                    'health',
                    'shopping',
                    'other',
                    'salary',
                    'freelance',
                    'investment',
                    'gift',
                ],
            },
            fromAccountName: {
                type: Type.STRING,
                description:
                    'Source account name (e.g. "Bank", "Cash"). Required for expense/transfer.',
            },
            toAccountName: {
                type: Type.STRING,
                description:
                    'Destination account name. Required for income/transfer.',
            },
            date: {
                type: Type.STRING,
                description: 'Date in YYYY-MM-DD format. Defaults to today.',
            },
            tagNames: {
                type: Type.ARRAY,
                description:
                    'Optional tag names (e.g. ["vacation", "reimbursable"])',
                items: { type: Type.STRING },
            },
            notes: {
                type: Type.STRING,
                description: 'Optional notes',
            },
            destinationAmount: {
                type: Type.NUMBER,
                description:
                    'For cross-currency transfers: the amount received in the destination currency. E.g., if selling 100 USD and getting 140000 ARS, amount=100, currency=USD, destinationAmount=140000, destinationCurrency=ARS.',
            },
            destinationCurrency: {
                type: Type.STRING,
                description:
                    'Currency code for the destination side of a cross-currency transfer.',
                enum: ['USD', 'ARS', 'EUR', 'BRL'],
            },
        },
        required: ['type', 'amount', 'description'],
    },
}

const updateTransactionTool: FunctionDeclaration = {
    name: 'updateTransaction',
    description:
        'Update an existing transaction. List transactions first to find the ID. Only include fields to change.',
    parameters: {
        type: Type.OBJECT,
        properties: {
            transactionId: {
                type: Type.STRING,
                description: 'The ID of the transaction to update',
            },
            amount: {
                type: Type.NUMBER,
                description: 'New amount. Only if changing.',
            },
            currency: {
                type: Type.STRING,
                description: 'New currency. Only if changing.',
                enum: ['USD', 'ARS', 'EUR', 'BRL'],
            },
            description: {
                type: Type.STRING,
                description: 'New description. Only if changing.',
            },
            category: {
                type: Type.STRING,
                description: 'New category. Only if changing.',
                enum: [
                    'groceries',
                    'transport',
                    'dining',
                    'entertainment',
                    'utilities',
                    'health',
                    'shopping',
                    'other',
                    'salary',
                    'freelance',
                    'investment',
                    'gift',
                ],
            },
            date: {
                type: Type.STRING,
                description: 'New date in YYYY-MM-DD. Only if changing.',
            },
            tagNames: {
                type: Type.ARRAY,
                description: 'New tags. Replaces existing tags.',
                items: { type: Type.STRING },
            },
            notes: {
                type: Type.STRING,
                description: 'New notes. Only if changing.',
            },
        },
        required: ['transactionId'],
    },
}

const deleteTransactionTool: FunctionDeclaration = {
    name: 'deleteTransaction',
    description:
        'Delete a transaction by ID. List transactions first to find the ID.',
    parameters: {
        type: Type.OBJECT,
        properties: {
            transactionId: {
                type: Type.STRING,
                description: 'The ID of the transaction to delete',
            },
        },
        required: ['transactionId'],
    },
}

const listTransactionsTool: FunctionDeclaration = {
    name: 'listTransactions',
    description:
        'List transactions. Supports filtering by type, date range, and category.',
    parameters: {
        type: Type.OBJECT,
        properties: {
            type: {
                type: Type.STRING,
                description: 'Filter by type. Optional.',
                enum: ['expense', 'income', 'transfer'],
            },
            startDate: {
                type: Type.STRING,
                description: 'Start date YYYY-MM-DD. Optional.',
            },
            endDate: {
                type: Type.STRING,
                description: 'End date YYYY-MM-DD. Optional.',
            },
            category: {
                type: Type.STRING,
                description: 'Filter by category name. Optional.',
                enum: [
                    'groceries',
                    'transport',
                    'dining',
                    'entertainment',
                    'utilities',
                    'health',
                    'shopping',
                    'other',
                    'salary',
                    'freelance',
                    'investment',
                    'gift',
                ],
            },
        },
        required: [],
    },
}

const getTransactionSummaryTool: FunctionDeclaration = {
    name: 'getTransactionSummary',
    description:
        'Get spending/income summary with totals and category breakdown. Call when user asks "how much did I spend".',
    parameters: {
        type: Type.OBJECT,
        properties: {
            startDate: {
                type: Type.STRING,
                description: 'Start date YYYY-MM-DD. Optional.',
            },
            endDate: {
                type: Type.STRING,
                description: 'End date YYYY-MM-DD. Optional.',
            },
        },
        required: [],
    },
}

const getAccountBalanceTool: FunctionDeclaration = {
    name: 'getAccountBalance',
    description:
        'Get the balance of a specific account. Call when user asks "how much do I have" or about their balance.',
    parameters: {
        type: Type.OBJECT,
        properties: {
            accountName: {
                type: Type.STRING,
                description:
                    'Account name (e.g. "Bank", "Cash", "Credit Card")',
            },
        },
        required: ['accountName'],
    },
}

const calculateTool: FunctionDeclaration = {
    name: 'calculate',
    description:
        'Evaluate a math expression safely. Use this for any arithmetic the user asks about — currency conversions, splitting bills, percentages, etc. Supports +, -, *, /, parentheses, and variables.',
    parameters: {
        type: Type.OBJECT,
        properties: {
            expression: {
                type: Type.STRING,
                description:
                    'Math expression to evaluate. E.g. "100 * 1400", "500 / 3", "0.1 + 0.2".',
            },
        },
        required: ['expression'],
    },
}

const fetchExchangeRateTool: FunctionDeclaration = {
    name: 'fetchExchangeRate',
    description:
        'Fetch the current exchange rate between two currencies from the internet. Use this when the user asks for a conversion rate or wants to convert an amount and did not provide the rate themselves.',
    parameters: {
        type: Type.OBJECT,
        properties: {
            fromCurrency: {
                type: Type.STRING,
                description: 'Source currency code.',
                enum: ['USD', 'ARS', 'EUR', 'BRL'],
            },
            toCurrency: {
                type: Type.STRING,
                description: 'Target currency code.',
                enum: ['USD', 'ARS', 'EUR', 'BRL'],
            },
        },
        required: ['fromCurrency', 'toCurrency'],
    },
}

const createAccountTool: FunctionDeclaration = {
    name: 'createAccount',
    description:
        'Create a new account for the user. Use this when the user has no accounts yet or wants to add a new one.',
    parameters: {
        type: Type.OBJECT,
        properties: {
            name: {
                type: Type.STRING,
                description:
                    'Account name (e.g. "Cash", "Bank", "Credit Card")',
            },
            type: {
                type: Type.STRING,
                description:
                    'Account type: "asset" for money the user has (bank, cash, savings), "liability" for money owed (credit card, loan)',
                enum: ['asset', 'liability'],
            },
            icon: {
                type: Type.STRING,
                description:
                    'Emoji icon for the account (e.g. "💵" for cash, "🏦" for bank, "💳" for credit card)',
            },
            currency: {
                type: Type.STRING,
                description: 'Default currency for this account',
                enum: ['USD', 'ARS', 'EUR', 'BRL'],
            },
        },
        required: ['name', 'type', 'icon', 'currency'],
    },
}

const listAccountsTool: FunctionDeclaration = {
    name: 'listAccounts',
    description:
        'List all user accounts. Use this to check if accounts exist before adding transactions, or when the user asks about their accounts.',
    parameters: {
        type: Type.OBJECT,
        properties: {},
        required: [],
    },
}

const TOOL_DECLARATIONS: FunctionDeclaration[] = [
    addTransactionTool,
    updateTransactionTool,
    deleteTransactionTool,
    listTransactionsTool,
    getTransactionSummaryTool,
    getAccountBalanceTool,
    calculateTool,
    fetchExchangeRateTool,
    createAccountTool,
    listAccountsTool,
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
