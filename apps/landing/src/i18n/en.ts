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
        getTheApp: 'Get the app',
    },

    hero: {
        // Mirrors the Spanish tape. These are translations of the verbatim
        // Spanish survey answers documented in `es.ts` — faithful in meaning
        // and register, but no longer the respondents' own words, which is why
        // they are not presented as quotations of an English speaker.
        quoteTape: {
            label: 'Reasons people stop tracking their expenses',
            chip: 'Why people stop logging',
            quotes: [
                '“It takes me too long to log every single one”',
                '“I didn’t last half a day”',
                '“The friction of having to remember, categorize and log every expense”',
                '“Entering them into the spreadsheet”',
                '“I forget — I don’t have anywhere to jot it down quickly”',
                '“Because doing it in the moment takes up too much time”',
                '“Sometimes I pay cash or throw out the receipt and I have no record of what I spent”',
                '“Having to enter and classify them manually”',
                '“The time I have to put into writing out the details of each expense.”',
                '“That I feel like it should be automatic”',
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

    problem: {
        title: 'Understanding where your money goes is far easier when it’s already written down.',
        body: 'The catch is that writing it down costs you. Buying something takes ten seconds; logging it properly takes longer — open the app, pick the category, type the amount, choose the account, save.',
        close: 'Wallet Bot takes that part off your hands. You tell it the expense, it gets logged, and by the end of the month it’s all in one place.',
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
            'Everything you need to understand where your money goes — and nothing else.',
        items: {
            voice: {
                title: 'Tell it, and it’s logged',
                body: 'Say “I paid 8,500 at the supermarket with my card” and that’s it. No fields, no lists, no picking a category: the assistant creates the account and category on the fly, and leaves an editable card in case it got something wrong.',
                types: {
                    expense: 'Expenses',
                    income: 'Income',
                    transfer: 'Transfers',
                    adjustment: 'Balance adjustments',
                },
            },
            offline: {
                title: 'Works without internet too',
                body: 'On your phone it’s saved anyway, and it catches up on its own once you’re back online.',
            },
            local: {
                title: 'No account needed',
                body: 'The mobile app works without signing up, and what you log stays on your device. You only need an account if you want it synced.',
            },
            fast: {
                title: 'The numbers update themselves',
                body: 'The moment you — or the assistant — log something, it’s in the lists, the balances and the charts. No reloads, no waiting.',
                chip: 'Zero spinners',
            },
            crossDevice: {
                title: 'On your phone and your computer',
                body: 'What you log on your phone shows up on your computer, and the other way round. It syncs across your devices on its own.',
            },
            dashboard: {
                title: 'Ask it how you’re doing',
                body: 'How much you’ve spent, on what, how much is left. Build your home screen with the widgets you want — stats, lists, pie, bar or line charts — or ask the assistant to build it for you.',
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
        },
    },

    download: {
        title: 'Try it free',
        subtitle: 'Now on Android, iPhone and the web.',
        android: {
            lead: 'Get it on',
            name: 'Google Play',
        },
        ios: {
            lead: 'Download on the',
            name: 'App Store',
        },
        web: {
            lead: 'Open beta',
            name: 'Web app',
        },
    },

    beta: {
        meta: {
            title: 'Wallet Bot — Get the app',
            description:
                'Wallet Bot is out on Android and iPhone. Fill out a short form to get the download links.',
        },
        chip: {
            android: 'Available on Android',
            ios: 'Available on iPhone',
        },
        heading: 'Get the app',
        body: 'It’s on Google Play and the App Store. To get it, fill out this short form. The download links are at the end.',
        formCta: {
            title: 'Fill out the form',
            body: 'It’s a couple of questions. Send it and you’ll see the links for Android and iPhone.',
        },
        webHeading: 'Or use it right now in your browser',
        webNotice: 'Nothing to install. The web app is open to anyone.',
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
