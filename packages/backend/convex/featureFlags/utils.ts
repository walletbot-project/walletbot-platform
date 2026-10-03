export type FlagKey =
    | 'agentGemini31'
    | 'agentLocalAccounts'
    | 'agentPromptSuggestions'
    | 'aiConsent'
    | 'agentReportButton'
    | 'debugToolCalls'
    | 'exchangeRates'
    | 'feedback'
    | 'recurringExpense'
    | 'whatsapp'

export const KNOWN_FLAGS: {
    key: FlagKey
    description: string
    enabledByDefault: boolean
}[] = [
    {
        key: 'agentGemini31',
        description:
            'Use Gemini 3.1 Flash Live on native 0.5.1+ and updated web clients for rollback/comparison tests, keeping the new audio architecture. Off uses Gemini 3.8 Live. Takes effect on the next token mint; existing connections stay on their model.',
        enabledByDefault: false,
    },
    {
        key: 'agentLocalAccounts',
        description:
            'Let native LOCAL accounts (no sign-in) mint a Gasti live token, so the agent works without an account. Off makes the agent sign-in only and local accounts are told to sign in.',
        enabledByDefault: true,
    },
    {
        key: 'agentPromptSuggestions',
        description:
            'Show per-user prompt suggestions on the empty Gasti screen, built on the device from the latest movements, accounts, categories and tags (native + web). Tapping one fills the input. Off shows the start screen without them.',
        enabledByDefault: false,
    },
    {
        key: 'aiConsent',
        description:
            'Ask for consent before the first agent session on iOS, naming the AI providers and the data sent to them (App Store guideline 5.1.2(i)). On by default; off skips the sheet and the server-side check. iOS only — Android and web never show it.',
        enabledByDefault: true,
    },
    {
        key: 'agentReportButton',
        description:
            'Show the flag icon on every agent response, the discoverable way to report it (native + web). Off leaves only the long-press action and the overflow menu.',
        enabledByDefault: true,
    },
    {
        key: 'debugToolCalls',
        description:
            'Show raw function-call debug JSON in the Gasti voice chat (native + web).',
        enabledByDefault: false,
    },
    {
        key: 'exchangeRates',
        description:
            'Declare the getExchangeRate tool to the Gasti agent (native + web) and let native cache the rate snapshot.',
        enabledByDefault: false,
    },
    {
        key: 'feedback',
        description:
            'Show the "Send feedback" action on the home screen (native + web).',
        enabledByDefault: false,
    },
    {
        key: 'recurringExpense',
        description:
            'Enable recurring movements: the recurrence controls in the manual form, the future movements screen, series editing and the agent recurrence tools (native + web).',
        enabledByDefault: false,
    },
    {
        key: 'whatsapp',
        description:
            'Let this account link a WhatsApp number and talk to Gasti there (native + web). Off hides the entry point, refuses new link codes, and answers a linked number with a short "not available" line instead of running the agent. Disconnecting an already-linked number always works, flag or no flag.',
        enabledByDefault: false,
    },
]

export const isKnownFlagKey = (key: string): key is FlagKey =>
    KNOWN_FLAGS.some((flag) => flag.key === key)
