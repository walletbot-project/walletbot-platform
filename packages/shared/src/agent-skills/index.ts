// Bundled agent skills — reference documents the model pulls on demand with
// the `readSkill` tool. The index (slug + one-liner) is rendered into the
// system prompt (SKILLS_INDEX in packages/backend/convex/live/createToken.ts);
// the bodies stay out of the prompt and load only when needed.
//
// They live in shared as constants so both clients execute `readSkill`
// locally (works offline, parity is compile-enforced on web and manifest-
// tested on native via the codegen). The accepted trade-off: updating a skill
// needs an app release on native.
//
// Accuracy rule: every claim in a body must match the code it describes.
// When the described behavior changes, change the skill in the same PR.

export type AgentSkill = {
    slug: string
    title: string
    /** One line for the prompt's skills index. */
    oneLiner: string
    /** The full document `readSkill` returns. */
    body: string
}

export const AGENT_SKILLS: readonly AgentSkill[] = [
    {
        slug: 'sync-and-offline',
        title: 'Sync & offline behavior',
        oneLiner:
            'How data syncs across devices, what works offline, and what happens on conflicts.',
        body: `# Sync & offline behavior

- The user's data (accounts, categories, tags, movements, saved filters, dashboard widgets) is one account shared across all their devices.
- On the native mobile app, everything you record is written to the device's local database first and synced to the account in the background. Recording, listing, editing and summaries all work with no connection; changes upload automatically when the device is back online and appear on the user's other devices shortly after.
- On the web app, changes go to the account directly, so they need a connection but appear on other devices as soon as those sync.
- Conflicts resolve last-write-wins per row: if the same entity was edited on two offline devices, the most recent edit survives.
- Deletes are soft everywhere: archived entities can be restored from the app, and deletions propagate across devices like any other change.
- Two ACTIVE accounts with the same name and the same currency are automatically merged into one when they sync (their movements are combined). Warn the user before creating an account whose name and currency match an existing active one, and prefer reusing the existing account.
- Very old app versions are blocked from syncing until updated (they keep working offline). If the user says their devices stopped syncing, an app update is the first thing to suggest.`,
    },
    {
        slug: 'accounts-and-currencies',
        title: 'Accounts & currencies',
        oneLiner:
            'Currency rules, default currency, same-name accounts, transfers and balance adjustments.',
        body: `# Accounts & currencies

- Every account has exactly one ISO 4217 currency, fixed at creation. It can never be changed; to "switch" a currency, create a new account and optionally transfer the balance.
- When the user creates an account without naming a currency, their default currency is applied automatically. The default currency lives in Settings and applies account-wide (all devices).
- A movement's currency always comes from its account — never ask the user for a movement currency.
- Two accounts may share a name only across different currencies. When a name matches several accounts, the one in the user's default currency wins automatically; otherwise ask which one, mentioning the currencies.
- Same name AND same currency is not allowed: sync auto-merges such duplicates (see sync-and-offline). Reuse the existing account instead of creating a twin.
- Transfers: same-currency transfers derive the received amount automatically. Cross-currency transfers require the amount received on the destination side (toAmount), or an exchangeRate to derive it. Transfers are excluded from category breakdowns and category summaries.
- Balance adjustment records the user's observed truth: pass balanceAfter exactly as the user stated it and the system computes the signed difference against the current balance. Never compute a "spent" amount yourself.
- Balances are per account, in that account's currency. There is no automatic currency conversion anywhere: totals never mix currencies meaningfully, so keep summaries and numeric widgets scoped to one currency.`,
    },
    {
        slug: 'dashboard-filters-cookbook',
        title: 'Dashboard filter cookbook',
        oneLiner:
            'Canonical filter JSON recipes: presets, ranges, tags, OR/NOT trees, cents.',
        body: `# Dashboard filter cookbook

Canonical filter JSON: a tree of groups {"combinator":"and"|"or","not"?:true,"children":[...]} and conditions {"field","operator","value",...}.

Fields and operators:
- type: operator "in", value subset of ["expense","income","transfer","balance_adjustment"].
- status: operator "in", value subset of ["pending","cleared"].
- date: operator "relative" with value one of "today","this_week","this_month","last_month","this_year"; or operator "between" with value {"from":"YYYY-MM-DD","to":"YYYY-MM-DD"} (inclusive calendar days).
- account: operator "in", value = account ids, plus "direction": "source"|"destination"|"either".
- category: operator "in", value = category ids.
- tag: operator "in", value = tag ids, optional "match":"any"|"all" and "includeSubtags":true.
- currency: operator "in", value = ISO codes, e.g. ["ARS"].
- amount: operator "between" (or ">=", "<="), value {"min":cents,"max":cents}. AMOUNTS IN FILTER JSON ARE CENTS: $500.00 is 50000.
- text: operator "contains", value = substring matched against name and description.

Always resolve human names to ids (the context snapshot carries them) before writing account/category/tag values.

Recipes:
- This month's expenses in ARS:
{"combinator":"and","children":[{"field":"type","operator":"in","value":["expense"]},{"field":"date","operator":"relative","value":"this_month"},{"field":"currency","operator":"in","value":["ARS"]}]}
- Food OR work tag:
{"combinator":"or","children":[{"field":"category","operator":"in","value":["<foodCategoryId>"]},{"field":"tag","operator":"in","value":["<workTagId>"],"match":"any"}]}
- (Food AND over $500) OR trip transport:
{"combinator":"or","children":[{"combinator":"and","children":[{"field":"category","operator":"in","value":["<foodId>"]},{"field":"amount","operator":"between","value":{"min":50000}}]},{"combinator":"and","children":[{"field":"category","operator":"in","value":["<transportId>"]},{"field":"tag","operator":"in","value":["<tripTagId>"]}]}]}
- Everything EXCEPT transfers:
{"combinator":"and","children":[{"combinator":"or","not":true,"children":[{"field":"type","operator":"in","value":["transfer"]}]}]}
- Money received into account X (either leg matters on transfers):
{"combinator":"and","children":[{"field":"account","operator":"in","value":["<accountId>"],"direction":"destination"}]}

Widget notes: numeric (stat sum/net) widgets should carry a currency condition; count-only stats need none. Balance widgets take NO filter — they use options currency/accountIds and are always as-of-now. Chart widgets exclude transfers regardless of the filter.`,
    },
    {
        slug: 'dates-and-time-confidence',
        title: 'Dates & time confidence',
        oneLiner:
            'The dateConfirmed/timeStatus contract and how natural-language dates resolve.',
        body: `# Dates & time confidence

Movements store both a calendar day and a clock, each with its own confidence signal. Getting these right is what makes the user's history trustworthy.

Accepted date inputs (resolved by the executor, identically on every platform): ISO dates ("2026-08-06", "2026-08-06T14:30:00"), "today"/"hoy", "yesterday"/"ayer", "anteayer", "tomorrow"/"mañana", "hace N días"/"N days ago", and deterministic relative weekdays ("el jueves pasado", "last thursday" — always the PREVIOUS occurrence, never today).

Rules:
- If the user gives no day, OMIT date entirely (the executor defaults to today) and set dateConfirmed false.
- If the user names any unambiguous day (including "ayer" or "el jueves pasado"), keep their expression in date and set dateConfirmed true. The executor re-derives the flag from date presence, so a wrong boolean cannot corrupt data — but send it correctly anyway.
- timeStatus is mandatory on creates:
  - "confirmed": the user said an exact clock ("a las 5 de la tarde" → time "17:00"). A numeric clock beats a range word.
  - "approximation": only a part-of-day cue. Map it to the representative clock and send it in time: morning/desayuno/mañana 10:00, lunch/almuerzo/mediodía 13:00, afternoon/merienda/tarde 16:00, dinner/cena/noche 22:00, madrugada 02:00.
  - "none": no clue about the hour. Send no time; the executor combines the day with the current clock so ordering inside the day stays natural.
- time is 24-hour HH:mm, required whenever timeStatus is confirmed or approximation (the create is rejected without it), and independent from date — an exact time with no day means: omit date, dateConfirmed false, send the time.
- updateTransaction: include timeStatus only when changing the day or the hour; a partial edit preserves whichever half (day/clock) you did not send. Omitting both leaves the stored timestamp untouched.`,
    },
    {
        slug: 'privacy-and-data',
        title: 'Privacy & data handling',
        oneLiner:
            'What is stored where, what leaves the device, exports, and account deletion.',
        body: `# Privacy & data handling

What to tell the user when they ask about their data:

- Financial data (accounts, movements, categories, tags, dashboards) belongs to their account and syncs to the backend so all their devices see it. On the native app a full local copy stays on the device and keeps working offline.
- Conversation history: for signed-in accounts, the transcript of these sessions and the tools you call (including their arguments and results, which can contain amounts and movement names) are stored with the account as session history. Raw audio never leaves the device — only transcripts do.
- You must never ask for or store passwords, card numbers, tokens or any credential. If the user dictates something that looks like a secret, do not persist it anywhere and say why.
- Deleting data: deleting a movement archives it (restorable from the app, and balances update immediately). Archiving accounts/categories/tags is likewise reversible.
- Deleting the ACCOUNT is different and final: the user requests it from Settings (or the website), receives an email link, and confirms by typing a word. It permanently erases their user and data and cannot be undone. You cannot trigger account deletion with tools — point them to Settings.
- Terms and Privacy Policy live at walletbot.live (per-language pages); the app records the user's acceptance.
- If the user asks to export their data: there is no self-service export surface yet. Do not promise one.`,
    },
]

/** Fast lookup by slug. */
export const AGENT_SKILLS_BY_SLUG: ReadonlyMap<string, AgentSkill> = new Map(
    AGENT_SKILLS.map((skill) => [skill.slug, skill]),
)
