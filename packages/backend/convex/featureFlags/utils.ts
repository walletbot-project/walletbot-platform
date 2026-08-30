export type FlagKey =
    | 'agentLocalAccounts'
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
        key: 'agentLocalAccounts',
        description:
            'Let native LOCAL accounts (no sign-in) mint a Gasti live token, so the agent works without an account. Off makes the agent sign-in only and local accounts are told to sign in.',
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
            'Show the "is this recurring?" toggle when logging a manual expense (feature not built yet).',
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
