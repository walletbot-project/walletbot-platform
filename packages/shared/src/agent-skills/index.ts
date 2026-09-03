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
        slug: 'recurring-movements',
        title: 'Recurring movements & future movements',
        oneLiner:
            'How repeating movements are stored, why they stay invisible until their date, and what "this one" vs "this and the future ones" does.',
        body: `# Recurring movements & future movements

## They are ordinary movements, created in advance
- A recurring rule is set up once, and its occurrences are created immediately as **real movements** with future dates. There is no "it will appear later" mechanism: the rows exist from the moment the rule is created.
- A future movement is invisible to everything that describes what already happened: absent from Activity, from account balances, from category and account summaries, and from every dashboard widget. It becomes visible on its own date, with no action from anyone.
- The cutoff is the end of the user's current day, so a movement dated today at 20:00 counts as having happened all day today rather than appearing at 20:00.
- So \`listTransactions\` and \`summarizeTransactions\` never show future movements. \`listUpcomingTransactions\` is the only way to see them.
- A one-off movement dated in the future behaves exactly the same way and also appears in \`listUpcomingTransactions\` — being in that list does not mean it repeats. Check whether the movement has a series before offering scope choices.

## "No end date" does not mean forever
- With an end date, every occurrence up to that day is created. "Monthly until 2036" is 120 movements.
- Without one, a fixed batch is created up front: 500 daily, 100 weekly, 48 monthly, 20 yearly. For "every N days" the batch follows the cadence N resembles. The create result reports the count and roughly how far it reaches — say that back to the user, because the app tells them the same thing and it is the honest answer to "forever?".
- When an open-ended series runs low, \`addRecurrenceOccurrences\` adds another batch. It continues from the **last occurrence that exists**, never from the one the user happened to mention: asking for more while looking at September, in a series already reaching November, means December onwards.
- A series with an end date cannot be extended that way — it is complete by the user's own choice. Moving the end is an edit to the rule.

## Editing and deleting: always ask the scope
- Every edit or delete of an occurrence has two possible meanings, and they are not interchangeable:
  - only-this — this one movement. The rest of the series is untouched.
  - all-future — this one and every later occurrence. Deleting also stops the rule there, so nothing new is created past it.
- ASK which one the user means. Never assume. "Borrá el alquiler" is ambiguous, and deleting one month when they meant the whole series cannot be undone in the app.
- Occurrences BEFORE the one being edited are never touched by either scope. To change what already happened, edit those movements individually.
- Changing the cadence only works with all-future, and splits the rule in two: the original ends at the previous occurrence and a new one starts here. Say so plainly — the earlier movements keep their old spacing, which is what the user asked for.

## Counting
- An occurrence's detail shows its position in the series ("the 3rd of 12") when the rule has an end date, and how far the series reaches when it does not.
- Both numbers count the movements that **exist**: delete one of five and the rest renumber. Never compute a position yourself by counting cadence steps from the start date — it will disagree with the app.`,
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
