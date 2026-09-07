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
        requestAccess: 'Request access',
    },

    hero: {
        liveLedger: {
            label: 'Live voice mode, logging expenses',
            amounts: [
                '−$12.00',
                '−$3.50',
                '−$18.20',
                '−$640.00',
                '+$1,200.00',
                '−$9.75',
            ],
        },
        headline: 'Say it. It’s already logged.',
        subheadline: {
            lead: 'Wallet Bot is a',
            highlight: 'personal expense tracker with a live voice mode',
            rest: ': tell it what you spent and the assistant writes it down for you. No spreadsheets. No forms. Just a conversation.',
        },
        ctaFeatures: 'See features',
    },

    stats: {
        currencies: { value: '50+', label: 'currencies supported' },
        types: { value: '4', label: 'movement types' },
        languages: { value: '2', label: 'languages in the app' },
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
            whatsapp: {
                title: 'Log it from WhatsApp',
                body: 'Send a message or a voice note on WhatsApp and the expense is written down, without opening the app.',
                chip: 'Coming soon',
            },
            filters: {
                title: 'Filters that remember',
                body: 'Search by text, combine conditions, and save your favorite views to come back to them in one tap.',
            },
            bilingual: {
                title: 'Spanish, English and more',
                body: 'The app comes in Spanish and English, and the assistant understands most languages: just talk to it in yours. Switch whenever you want, even mid-conversation.',
                chipMore: '+ many more',
            },
        },
    },

    download: {
        title: 'Try it free',
        subtitle:
            'The web app is open now. Android is in closed beta and iPhone is coming soon.',
        android: {
            lead: 'Closed beta on',
            name: 'Google Play',
        },
        ios: {
            lead: 'Coming soon on',
            name: 'App Store',
        },
        web: {
            lead: 'Open beta',
            name: 'Web app',
        },
    },

    beta: {
        meta: {
            title: 'Wallet Bot — Request beta access',
            description:
                'Join the Wallet Bot closed beta on Android and be the first to know when the iPhone app lands.',
        },
        chip: {
            android: 'Android in closed beta',
            ios: 'iPhone coming soon',
        },
        heading: 'Request beta access',
        body: 'Android is in closed beta: leave us your email and we’ll add you to the tester list.',
        formCta: {
            title: 'Fill out the form',
            body: 'It’s a couple of questions. We’ll email you once you’re on the list.',
        },
        iosNote:
            'On iPhone? Fill it out anyway. We use the same list to let you know the moment the app lands on the App Store.',
        webHeading: 'Or use it right now in your browser',
        webNotice: 'No need to wait: the web app is open to anyone.',
        webCta: 'Open the web app',
        backHome: 'Back to home',
    },

    support: {
        meta: {
            title: 'Wallet Bot — Support',
            description:
                'Write to us by email: the Wallet Bot support address.',
        },
        heading: 'Support',
        body: 'Any question, trouble with the app or request about your account, write to us by email.',
        emailLabel: 'Write to us at',
        email: 'support@walletbot.live',
        emailSubject: 'Wallet Bot support',
        backHome: 'Back to home',
    },

    footer: {
        tagline: 'A simple, conversational personal expense tracker.',
        support: 'Support',
        privacy: 'Privacy Policy',
        terms: 'Terms and Conditions',
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
