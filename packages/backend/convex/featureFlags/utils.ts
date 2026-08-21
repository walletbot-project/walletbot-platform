export type FlagKey = 'debugToolCalls' | 'feedback' | 'recurringExpense'

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
        key: 'feedback',
        description:
            'Show the "Send feedback" card on the home screen (native + web), which opens the report form with file attachments.',
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
