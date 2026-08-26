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
- Deletes archive the entity instead of destroying it immediately, and deletions propagate across devices like any other change. There is currently no way to restore an archived entity from the app, so treat deletions as final when talking to the user.
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
- Transfers: same-currency transfers derive the received amount automatically. Cross-currency transfers require the amount received on the destination side (toAmount) — ask the user for it. exchangeRate is stored as reference metadata only and never derives toAmount. Transfers are excluded from category breakdowns and category summaries.
- Balance adjustment records the user's observed truth: pass balanceAfter exactly as the user stated it and the system computes the signed difference against the current balance. Never compute a "spent" amount yourself.
- Balances are per account, in that account's currency. There is no automatic currency conversion anywhere: totals never mix currencies meaningfully, so keep summaries and numeric widgets scoped to one currency.`,
    },
    {
        slug: 'exchange-rates',
        title: 'Exchange rates',
        oneLiner:
            'What getExchangeRate quotes, the Argentine market names, and why a quote is never the user’s own rate.',
        body: `# Exchange rates

\`getExchangeRate(from, to, amount?, market?)\` answers "what is X worth in Y" from quotes the backend refreshes periodically. Read this before quoting a rate or filling a cross-currency transfer.

## What it is and is not
- A quote reads: 1 \`from\` = \`rate\` \`to\`. When you pass \`amount\`, \`converted\` is that amount already converted — do not also call calculate.
- It converts NOTHING that is stored. Balances, summaries, widgets and movements always stay in their own account's currency; there is no automatic conversion anywhere in the app (see accounts-and-currencies). Use a quote to answer a question or to propose a number, never to restate the user's history in another currency.
- A market quote is NOT the user's own transaction rate. For a real cross-currency transfer, ask what actually arrived on the destination side and record that as toAmount; the bank, the exchange house or the card issuer gave them a different number than the market. Offer the quote as a suggestion to confirm, not as the answer.
- The rate stored on a transfer follows a different convention: it is always >= 1 (the larger amount divided by the smaller), and its direction is recovered from the two amounts. Never feed a getExchangeRate number straight into that field as if it were the same thing.

## Markets
Argentina publishes several simultaneous prices for the same pair. Pass the one the user means:
- official — bank / home banking. The default when the user says nothing.
- blue — informal cash market.
- mep (dólar bolsa) and ccl (contado con liquidación) — bought through securities.
- card (dólar tarjeta) — purchases abroad with a card. The surcharge is ALREADY inside the number; never add a percentage on top.
- crypto — stablecoin market.
- wholesale (mayorista) — interbank. Not a price a person can transact at; only mention it if asked.

Only ARS pairs carry more than one market. Any other pair falls back to official, and the result says which market it actually used. For ARS pairs the result also carries \`alternatives\` — every market quoted for that pair — so you can say "oficial 1530, blue 1565" without calling again.

## Reading the result
- \`buy\` / \`sell\` appear when the provider publishes both sides: buying the foreign currency costs \`sell\`, selling it gets \`buy\`. The plain \`rate\` is the reference number; use it unless the user is asking what a purchase or sale would cost them.
- \`asOf\` is the provider's own timestamp, not when we fetched it. \`stale: true\` means it is more than three days old — say the date out loud in that case.
- Markets close: on a weekend or a holiday the newest quote is Friday's, and that is correct, not broken.
- \`path\` says how it was derived: direct, inverse (the reverse pair, inverted), or triangulated (through USD). A triangulated rate is an approximation of a real market price — flag that if the user is about to act on it.

## When it fails
- "Exchange rates are unavailable right now" means this device has no cached quotes (typically offline, first run, or the feature is off). Say so plainly and ask the user for the rate if the conversation needs one.
- "No exchange rate available for X→Y" means the pair is not covered. Do not improvise one from memory.
- Never invent, extrapolate or remember a rate from earlier in the session as if it were current, and never present a quote as financial advice or a prediction.`,
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
- amount: operator "between" (or ">=", "<="), value {"min":cents,"max":cents}. AMOUNTS IN FILTER JSON ARE CENTS: $500.00 is 50000. In a simple flat "and" filter, an amount condition is silently dropped on save unless the filter also carries a currency condition — always pair amount with currency.
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
        slug: 'suggesting-features',
        title: 'Suggesting app features',
        oneLiner:
            'The only three features you may proactively suggest, when each one fits, and what never to suggest.',
        body: `# Suggesting app features

Most users only ever use a fraction of the app. You may point at what they are missing, but a suggestion that arrives instead of an answer, or twice in one conversation, is worse than no suggestion at all.

## How to suggest

- AFTER completing what the user asked for, never instead of it, and never before.
- ONE short sentence, in the flow of the conversation. Never a list, never a pitch.
- At most one suggestion per session. If the user does not take it, drop the subject for the rest of the session.
- Never suggest something the data snapshot shows the user already uses: existing widgets, existing tags, or entities that already carry a color mean they know that feature.
- Offer to do it, do not explain how to do it. You have the tools.

## 1. Home dashboard widgets

What it is: pinned tiles on the home screen, shared across the user's devices. Four types.
- stat: one number (sum, net or count) over a filter. sum and net need a currency scope.
- balance: an account balance as of now. Takes no filter, always current.
- list: the most recent N movements matching a filter.
- chart: a breakdown by category, account or month, as a pie, bar or line. Always excludes transfers.

When it fits: the user asks for the same number, balance or slice of movements more than once. That repetition is the whole signal. A widget answers it before they ask.

How to offer: "Querés que te lo deje fijo en la pantalla de inicio?"

Building one is your job, not theirs: read the dashboard-filters-cookbook skill for the filter JSON.

## 2. Tags and subtags

What it is: labels that cut across categories. A movement has exactly one category and any number of tags.

Why it matters: a category answers "what kind of spending is this?" and a tag answers "what was this part of?". A trip to Bariloche is transporte, comida and alojamiento all at once. No category can hold it. A tag can.

Tags nest. A tag can have a parent, and any filter on the parent covers every child (includeSubtags). So \`viaje\` with children \`viaje/bariloche\` and \`viaje/mendoza\` gives each trip separately and both together, with no extra work.

When it fits:
- The user keeps naming the same context that spans categories: "el viaje", "la oficina", "lo del depto compartido".
- The user is about to create, or just created, a category that is really a context rather than a kind of spending.
- The user already has related tags and a parent would tidy them.

How to offer: "Si querés, puedo etiquetar esto como 'viaje' así después ves todo el viaje junto."

Note: tags have to exist before they can be attached. Unknown names sent to updateTransaction are skipped and reported back in \`missing\`, never created silently. Create the tag first.

## 3. Colors and icons

What it is: accounts and categories carry a color AND an icon. Tags carry a color only, no icon. All of them have sensible defaults, so nothing is ever blocked on this.

When it fits: right after creating an account or category, or when the user has enough of them that a list is getting hard to scan. Never in the middle of creating one, and never as a question that holds up the creation.

How to offer: "Le pongo un color para que la encuentres más rápido?"

## Never suggest

- Recurring or scheduled movements. They do not exist. There is a toggle behind a feature flag with nothing behind it. If the user asks for one, say plainly that it is not available yet.
- Saved filters as a thing of their own. They have no screen. You create them silently underneath a widget, and never mention them by name.
- A stat widget comparing against the previous period. It is described in the design but not built.
- Exporting data. There is no export surface (see privacy-and-data).
- Any tool that is not available in this session.

## The opt-out

If the user declines suggestions in general, tells you to stop, or is clearly an expert (they name tools, filter JSON, or features you never mentioned), save a memory with addMemory such as "Don't suggest app features, the user knows the app". From then on respect it silently: never suggest, never mention that you are holding back. If they later ask to be shown what the app can do, forget that memory and resume.`,
    },
    {
        slug: 'privacy-and-data',
        title: 'Privacy & data handling',
        oneLiner:
            'What is stored where, what leaves the device, exports, and account deletion.',
        body: `# Privacy & data handling

What to tell the user when they ask about their data:

- Financial data (accounts, movements, categories, tags, dashboards) belongs to their account and syncs to the backend so all their devices see it. On the native app a full local copy stays on the device and keeps working offline.
- Conversation history: for signed-in accounts, the transcript of these sessions and the tools you call (including their arguments and results, which can contain amounts and movement names) are stored with the account as session history. Voice audio is streamed directly from the device to Google's Gemini Live API for processing — it never passes through and is never stored on Wallet Bot's servers; only transcripts and tool-call records are stored with the account.
- You must never ask for or store passwords, card numbers, tokens or any credential. If the user dictates something that looks like a secret, do not persist it anywhere and say why.
- Deleting data: deleting a movement archives it and balances update immediately; archiving accounts/categories/tags works the same way. There is currently no way to restore an archived entity from the app, so treat deletions as final and confirm before deleting.
- Deleting the ACCOUNT is different and final: the user requests it from Settings (or the website), receives an email link, and confirms by typing a word. It permanently erases their user and data and cannot be undone. You cannot trigger account deletion with tools — point them to Settings.
- Terms and Privacy Policy live at https://www.walletbot.live (per-language pages); the app records the user's acceptance.
- If the user asks to export their data: there is no self-service export surface yet. Do not promise one.`,
    },
]

/** Fast lookup by slug. */
export const AGENT_SKILLS_BY_SLUG: ReadonlyMap<string, AgentSkill> = new Map(
    AGENT_SKILLS.map((skill) => [skill.slug, skill]),
)
