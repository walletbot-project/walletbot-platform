// GENERATED FILE — DO NOT EDIT.
//
// Source: packages/shared (tools/constants.ts, tools/definitions.ts).
// Regenerate with `pnpm run generate:agent` from packages/shared.
// The freshness test lives at packages/shared/test/agent-codegen.test.ts.

/// The Gemini Live model the backend mints tokens for.
const String kAgentModel = 'gemini-3.1-flash-live-preview';

/// The prebuilt voice negotiated into the session.
const String kAgentVoiceName = 'Rasalgethi';

/// Every tool the token declares, in declaration order. The native
/// executor switch must cover exactly this set (tool_manifest_test.dart).
const List<String> kAgentToolNames = [
  'listAccounts',
  'getAccount',
  'getAccountBalance',
  'createAccount',
  'updateAccount',
  'archiveAccount',
  'listCategories',
  'getCategory',
  'createCategory',
  'updateCategory',
  'archiveCategory',
  'listTags',
  'getTag',
  'createTag',
  'updateTag',
  'archiveTag',
  'listTransactions',
  'getTransaction',
  'addExpense',
  'addIncome',
  'addTransfer',
  'addBalanceAdjustment',
  'updateTransaction',
  'deleteTransaction',
  'summarizeTransactions',
  'listSavedFilters',
  'createSavedFilter',
  'updateSavedFilter',
  'archiveSavedFilter',
  'listDashboardWidgets',
  'createDashboardWidget',
  'updateDashboardWidget',
  'reorderDashboardWidgets',
  'archiveDashboardWidget',
  'addMemory',
  'updateMemory',
  'forgetMemory',
  'updateSettings',
  'readSkill',
];

/// Per-list caps of the mint context payload (abuse prevention;
/// enforced server-side by sanitizeAgentContext).
const int kAgentContextAccountsCap = 100;
const int kAgentContextCategoriesCap = 200;
const int kAgentContextTagsCap = 200;
const int kAgentContextRecentTransactionsCap = 50;
const int kAgentContextMemoriesCap = 200;

/// A bundled agent skill — see packages/shared/src/agent-skills.
class AgentSkill {
  const AgentSkill({
    required this.slug,
    required this.title,
    required this.body,
  });

  final String slug;
  final String title;
  final String body;
}

/// The reference documents the `readSkill` tool serves, offline.
const List<AgentSkill> kAgentSkills = [
  AgentSkill(
    slug: 'sync-and-offline',
    title: 'Sync & offline behavior',
    body:
        '# Sync & offline behavior\n\n- The user\'s data (accounts, categories, tags, movements, saved filters, dashboard widgets) is one account shared across all their devices.\n- On the native mobile app, everything you record is written to the device\'s local database first and synced to the account in the background. Recording, listing, editing and summaries all work with no connection; changes upload automatically when the device is back online and appear on the user\'s other devices shortly after.\n- On the web app, changes go to the account directly, so they need a connection but appear on other devices as soon as those sync.\n- Conflicts resolve last-write-wins per row: if the same entity was edited on two offline devices, the most recent edit survives.\n- Deletes are soft everywhere: archived entities can be restored from the app, and deletions propagate across devices like any other change.\n- Two ACTIVE accounts with the same name and the same currency are automatically merged into one when they sync (their movements are combined). Warn the user before creating an account whose name and currency match an existing active one, and prefer reusing the existing account.\n- Very old app versions are blocked from syncing until updated (they keep working offline). If the user says their devices stopped syncing, an app update is the first thing to suggest.',
  ),
  AgentSkill(
    slug: 'accounts-and-currencies',
    title: 'Accounts & currencies',
    body:
        '# Accounts & currencies\n\n- Every account has exactly one ISO 4217 currency, fixed at creation. It can never be changed; to "switch" a currency, create a new account and optionally transfer the balance.\n- When the user creates an account without naming a currency, their default currency is applied automatically. The default currency lives in Settings and applies account-wide (all devices).\n- A movement\'s currency always comes from its account — never ask the user for a movement currency.\n- Two accounts may share a name only across different currencies. When a name matches several accounts, the one in the user\'s default currency wins automatically; otherwise ask which one, mentioning the currencies.\n- Same name AND same currency is not allowed: sync auto-merges such duplicates (see sync-and-offline). Reuse the existing account instead of creating a twin.\n- Transfers: same-currency transfers derive the received amount automatically. Cross-currency transfers require the amount received on the destination side (toAmount), or an exchangeRate to derive it. Transfers are excluded from category breakdowns and category summaries.\n- Balance adjustment records the user\'s observed truth: pass balanceAfter exactly as the user stated it and the system computes the signed difference against the current balance. Never compute a "spent" amount yourself.\n- Balances are per account, in that account\'s currency. There is no automatic currency conversion anywhere: totals never mix currencies meaningfully, so keep summaries and numeric widgets scoped to one currency.',
  ),
  AgentSkill(
    slug: 'dashboard-filters-cookbook',
    title: 'Dashboard filter cookbook',
    body:
        '# Dashboard filter cookbook\n\nCanonical filter JSON: a tree of groups {"combinator":"and"|"or","not"?:true,"children":[...]} and conditions {"field","operator","value",...}.\n\nFields and operators:\n- type: operator "in", value subset of ["expense","income","transfer","balance_adjustment"].\n- status: operator "in", value subset of ["pending","cleared"].\n- date: operator "relative" with value one of "today","this_week","this_month","last_month","this_year"; or operator "between" with value {"from":"YYYY-MM-DD","to":"YYYY-MM-DD"} (inclusive calendar days).\n- account: operator "in", value = account ids, plus "direction": "source"|"destination"|"either".\n- category: operator "in", value = category ids.\n- tag: operator "in", value = tag ids, optional "match":"any"|"all" and "includeSubtags":true.\n- currency: operator "in", value = ISO codes, e.g. ["ARS"].\n- amount: operator "between" (or ">=", "<="), value {"min":cents,"max":cents}. AMOUNTS IN FILTER JSON ARE CENTS: \$500.00 is 50000.\n- text: operator "contains", value = substring matched against name and description.\n\nAlways resolve human names to ids (the context snapshot carries them) before writing account/category/tag values.\n\nRecipes:\n- This month\'s expenses in ARS:\n{"combinator":"and","children":[{"field":"type","operator":"in","value":["expense"]},{"field":"date","operator":"relative","value":"this_month"},{"field":"currency","operator":"in","value":["ARS"]}]}\n- Food OR work tag:\n{"combinator":"or","children":[{"field":"category","operator":"in","value":["<foodCategoryId>"]},{"field":"tag","operator":"in","value":["<workTagId>"],"match":"any"}]}\n- (Food AND over \$500) OR trip transport:\n{"combinator":"or","children":[{"combinator":"and","children":[{"field":"category","operator":"in","value":["<foodId>"]},{"field":"amount","operator":"between","value":{"min":50000}}]},{"combinator":"and","children":[{"field":"category","operator":"in","value":["<transportId>"]},{"field":"tag","operator":"in","value":["<tripTagId>"]}]}]}\n- Everything EXCEPT transfers:\n{"combinator":"and","children":[{"combinator":"or","not":true,"children":[{"field":"type","operator":"in","value":["transfer"]}]}]}\n- Money received into account X (either leg matters on transfers):\n{"combinator":"and","children":[{"field":"account","operator":"in","value":["<accountId>"],"direction":"destination"}]}\n\nWidget notes: numeric (stat sum/net) widgets should carry a currency condition; count-only stats need none. Balance widgets take NO filter — they use options currency/accountIds and are always as-of-now. Chart widgets exclude transfers regardless of the filter.',
  ),
  AgentSkill(
    slug: 'dates-and-time-confidence',
    title: 'Dates & time confidence',
    body:
        '# Dates & time confidence\n\nMovements store both a calendar day and a clock, each with its own confidence signal. Getting these right is what makes the user\'s history trustworthy.\n\nAccepted date inputs (resolved by the executor, identically on every platform): ISO dates ("2026-08-06", "2026-08-06T14:30:00"), "today"/"hoy", "yesterday"/"ayer", "anteayer", "tomorrow"/"mañana", "hace N días"/"N days ago", and deterministic relative weekdays ("el jueves pasado", "last thursday" — always the PREVIOUS occurrence, never today).\n\nRules:\n- If the user gives no day, OMIT date entirely (the executor defaults to today) and set dateConfirmed false.\n- If the user names any unambiguous day (including "ayer" or "el jueves pasado"), keep their expression in date and set dateConfirmed true. The executor re-derives the flag from date presence, so a wrong boolean cannot corrupt data — but send it correctly anyway.\n- timeStatus is mandatory on creates:\n  - "confirmed": the user said an exact clock ("a las 5 de la tarde" → time "17:00"). A numeric clock beats a range word.\n  - "approximation": only a part-of-day cue. Map it to the representative clock and send it in time: morning/desayuno/mañana 10:00, lunch/almuerzo/mediodía 13:00, afternoon/merienda/tarde 16:00, dinner/cena/noche 22:00, madrugada 02:00.\n  - "none": no clue about the hour. Send no time; the executor combines the day with the current clock so ordering inside the day stays natural.\n- time is 24-hour HH:mm, required whenever timeStatus is confirmed or approximation (the create is rejected without it), and independent from date — an exact time with no day means: omit date, dateConfirmed false, send the time.\n- updateTransaction: include timeStatus only when changing the day or the hour; a partial edit preserves whichever half (day/clock) you did not send. Omitting both leaves the stored timestamp untouched.',
  ),
  AgentSkill(
    slug: 'privacy-and-data',
    title: 'Privacy & data handling',
    body:
        '# Privacy & data handling\n\nWhat to tell the user when they ask about their data:\n\n- Financial data (accounts, movements, categories, tags, dashboards) belongs to their account and syncs to the backend so all their devices see it. On the native app a full local copy stays on the device and keeps working offline.\n- Conversation history: for signed-in accounts, the transcript of these sessions and the tools you call (including their arguments and results, which can contain amounts and movement names) are stored with the account as session history. Raw audio never leaves the device — only transcripts do.\n- You must never ask for or store passwords, card numbers, tokens or any credential. If the user dictates something that looks like a secret, do not persist it anywhere and say why.\n- Deleting data: deleting a movement archives it (restorable from the app, and balances update immediately). Archiving accounts/categories/tags is likewise reversible.\n- Deleting the ACCOUNT is different and final: the user requests it from Settings (or the website), receives an email link, and confirms by typing a word. It permanently erases their user and data and cannot be undone. You cannot trigger account deletion with tools — point them to Settings.\n- Terms and Privacy Policy live at walletbot.live (per-language pages); the app records the user\'s acceptance.\n- If the user asks to export their data: there is no self-service export surface yet. Do not promise one.',
  ),
];
