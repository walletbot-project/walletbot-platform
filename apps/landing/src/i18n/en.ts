import type { Messages } from './es'

/**
 * English catalog. Typed as `Messages`, so `tsc` rejects a missing key, a stray
 * key, or a value function whose parameters drifted from the reference locale —
 * no separate key-parity test needed.
 */
export const en: Messages = {
    meta: {
        title: 'Wallet Bot — Expenses, logged by voice',
        description:
            'A simple, fast, modern personal expense tracker. Just talk and your expenses are logged: no spreadsheets, no tedious forms. Just a conversation.',
    },

    nav: {
        skipToContent: 'Skip to content',
        languageLabel: 'Language',
        features: 'Features',
        download: 'Download',
        getApp: 'Get the app',
    },

    hero: {
        badge: 'Live voice mode',
        headline: 'Say it. It’s already logged.',
        subheadline:
            'Wallet Bot is a personal expense tracker with a live voice mode: tell it what you spent and the assistant writes it down for you. No spreadsheets. No forms. Just a conversation.',
        ctaFeatures: 'See features',
    },

    stats: {
        currencies: { value: '50+', label: 'currencies supported' },
        types: { value: '4', label: 'movement types' },
        languages: { value: '2', label: 'languages, one assistant' },
        offline: { value: '100%', label: 'offline-first on your phone' },
    },

    demo: {
        listening: 'Listening',
        userSays: '“Paid 12 dollars for groceries with my card”',
        actionType: 'Expense',
        actionName: 'Groceries',
        actionAccount: 'Card',
        actionAmount: '$12.00',
        logged: 'Logged — tap the card to fix anything',
    },

    features: {
        title: 'Simple on purpose',
        subtitle:
            'Everything you need to know where your money goes — and nothing else.',
        items: {
            voice: {
                title: 'Live voice assistant',
                body: 'Just talk and it’s saved: it creates accounts and categories on the fly, and every action shows up as an editable card so you can fix anything on the spot.',
                types: {
                    expense: 'Expenses',
                    income: 'Income',
                    transfer: 'Transfers',
                    adjustment: 'Balance adjustments',
                },
            },
            offline: {
                title: 'Works offline',
                body: 'The mobile app keeps everything on your phone and syncs across your devices on its own once you’re back online.',
            },
            local: {
                title: 'Local mode, no account',
                body: 'Use the mobile app without signing up: your financial records stay on your device.',
            },
            fast: {
                title: 'Actually fast',
                body: 'No reloads, no waiting: the moment you — or the assistant — log something, it shows up in lists, balances and charts.',
                chip: 'Zero spinners',
            },
            currencies: {
                title: 'Multi-currency',
                body: 'Accounts in 50+ currencies, cross-currency transfers with exchange rates, and totals always kept separate per currency.',
            },
            dashboard: {
                title: 'A home screen that’s yours',
                body: 'Build the mobile app’s home with widgets: stats, lists, and pie, bar or line charts. The assistant can even build it for you.',
            },
            filters: {
                title: 'Filters that remember',
                body: 'Search by text, combine conditions, and save your favorite views to come back to them in one tap.',
            },
            bilingual: {
                title: 'Spanish and English',
                body: 'The app and the assistant speak both. Switch whenever you want, even mid-conversation.',
            },
        },
    },

    download: {
        title: 'Download it free',
        subtitle: 'On Android today. iPhone coming soon.',
        android: {
            lead: 'Get it on',
            name: 'Google Play',
        },
        ios: {
            lead: 'Coming soon on',
            name: 'App Store',
        },
    },

    footer: {
        tagline: 'A simple, conversational personal expense tracker.',
        privacy: 'Privacy Policy',
        terms: 'Terms and Conditions',
        webApp: 'Web app (beta)',
        copyright: (p) => `© ${p.year} Wallet Bot`,
    },

    legal: {
        privacy: {
            title: 'Privacy Policy',
            description:
                'How Wallet Bot collects, uses and protects your personal data.',
        },
        terms: {
            title: 'Terms and Conditions',
            description: 'The terms governing your use of Wallet Bot.',
        },
        backHome: 'Back to home',
    },
}
