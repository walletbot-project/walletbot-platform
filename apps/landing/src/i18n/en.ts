import type { Messages } from './es'

/**
 * English catalog. Typed as `Messages`, so `tsc` rejects a missing key, a stray
 * key, or a value function whose parameters drifted from the reference locale —
 * no separate key-parity test needed.
 */
export const en: Messages = {
    meta: {
        title: 'Wallet Bot',
        description: 'Keep track of your personal expenses.',
    },

    nav: {
        skipToContent: 'Skip to content',
        languageLabel: 'Language',
    },

    home: {
        headline: 'Wallet Bot',
        subheadline: 'Keep track of your personal expenses.',
        setupNotice: (p) => `Scaffold ready. Active locale: ${p.locale}.`,
    },
}
