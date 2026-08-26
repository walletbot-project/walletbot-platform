export type FlagKey =
    | 'debugToolCalls'
    | 'exchangeRates'
    | 'feedback'
    | 'recurringExpense'

export const KNOWN_FLAGS: {
    key: FlagKey
    description: string
    enabledByDefault: boolean
}[] = [
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
]

export const isKnownFlagKey = (key: string): key is FlagKey =>
    KNOWN_FLAGS.some((flag) => flag.key === key)
